//
//  MergeKit.swift
//
//  The shared machinery of `Publishers.Merge`, `Publishers.CombineLatest` and
//  `Publishers.MergeMany`: the parts that do not depend on how many upstreams there are,
//  and so are written once for all three families. What does depend on the arity (the
//  stored properties, the `init`, and the tuple the combined publisher produces) is
//  written out per arity in `Publishers.Merge.swift` and `Publishers.CombineLatest.swift`.
//

import CombineHelpers

// MARK: - Publishers.Merge

/// The subscription a merged publisher hands downstream, and at the same time the
/// subscriber it hands to every upstream. Both the upstreams and the downstream speak
/// the same `Output` and `Failure`, so one object serves all of them.
internal final class MergeInner<Output, Failure: Error, Downstream: Subscriber>: Subscription, Subscriber
    where Downstream.Input == Output, Downstream.Failure == Failure
{
    typealias Input = Output

    private enum State {
        case awaitingSubscriptions
        case active
        case terminated
    }

    private let lock = UnfairLock.allocate()
    private let downstream: Downstream
    private let expectedUpstreamCount: Int

    private var state: State = .awaitingSubscriptions
    private var upstreamSubscriptions: [Subscription] = []
    private var receivedUpstreamCount = 0
    private var remainingUpstreamCount: Int
    private var downstreamDemand: Subscribers.Demand = .none
    private var didRequestUpstream = false

    init(downstream: Downstream, upstreamCount: Int) {
        self.downstream = downstream
        self.expectedUpstreamCount = upstreamCount
        self.remainingUpstreamCount = upstreamCount
    }

    deinit {
        lock.deallocate()
    }

    // MARK: Subscription

    func request(_ demand: Subscribers.Demand) {
        lock.lock()
        guard case .active = state, demand > .none else {
            lock.unlock()
            return
        }
        downstreamDemand += demand
        // Every upstream of a merged publisher is asked for as much as it will give:
        // there is no per-upstream buffer to hold a value in, so upstream demand cannot
        // be shaped by downstream demand. A value that arrives with no demand behind it
        // is dropped, which is what Apple's documentation for the operator says it does.
        let shouldRequestUpstream = !didRequestUpstream
        didRequestUpstream = true
        let subscriptions = shouldRequestUpstream ? upstreamSubscriptions : []
        lock.unlock()

        for subscription in subscriptions {
            subscription.request(.unlimited)
        }
    }

    func cancel() {
        lock.lock()
        guard case .terminated = state else {
            state = .terminated
            let subscriptions = upstreamSubscriptions
            upstreamSubscriptions = []
            lock.unlock()
            for subscription in subscriptions {
                subscription.cancel()
            }
            return
        }
        lock.unlock()
    }

    // MARK: Subscriber

    func receive(subscription: Subscription) {
        lock.lock()
        guard case .awaitingSubscriptions = state else {
            lock.unlock()
            subscription.cancel()
            return
        }
        upstreamSubscriptions.append(subscription)
        receivedUpstreamCount += 1
        // The downstream learns of the subscription only once every upstream has
        // arrived, so that the demand it asks for is answered to all of them.
        guard receivedUpstreamCount == expectedUpstreamCount else {
            lock.unlock()
            return
        }
        state = .active
        lock.unlock()
        downstream.receive(subscription: self)
    }

    func receive(_ input: Output) -> Subscribers.Demand {
        lock.lock()
        guard case .active = state, downstreamDemand > .none else {
            lock.unlock()
            return .none
        }
        downstreamDemand -= 1
        lock.unlock()
        let additionalDemand = downstream.receive(input)
        if additionalDemand > .none {
            lock.lock()
            downstreamDemand += additionalDemand
            lock.unlock()
        }
        return .none
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        lock.lock()
        switch completion {
        case .failure(let error):
            guard case .terminated = state else {
                state = .terminated
                let subscriptions = upstreamSubscriptions
                upstreamSubscriptions = []
                lock.unlock()
                for subscription in subscriptions {
                    subscription.cancel()
                }
                downstream.receive(completion: .failure(error))
                return
            }
            lock.unlock()
        case .finished:
            // One object is the subscriber of every upstream, so a completion does not
            // say which upstream sent it; the merged publisher only ever needs to know
            // that one more of them is done. A subscription that has already finished
            // stays in the list until cancellation, which is a no-op on it.
            remainingUpstreamCount -= 1
            guard case .terminated = state, remainingUpstreamCount > 0 else {
                state = .terminated
                lock.unlock()
                downstream.receive(completion: .finished)
                return
            }
            lock.unlock()
        }
    }
}

// MARK: - Publishers.CombineLatest

/// What the combined publisher needs to know about one of its upstreams, whatever that
/// upstream's output type is: whether it holds a value, and the subscription it arrived
/// on. The value itself is read by the arity, which knows the type.
internal protocol CombineLatestChildProtocol: Subscriber {
    var hasValue: Bool { get }
    var upstream: Subscription? { get }
    func clearValue()
}

/// The subscriber handed to one upstream of a `combineLatest` publisher. It keeps that
/// upstream's most recent value and asks for one value at a time.
internal final class CombineLatestChild<ChildInput, CombinedOutput, CombinedFailure: Error,
                                      Downstream: Subscriber>: CombineLatestChildProtocol
    where Downstream.Input == CombinedOutput, Downstream.Failure == CombinedFailure
{
    typealias Input = ChildInput

    typealias Failure = CombinedFailure

    private let parent: CombineLatestInner<CombinedOutput, CombinedFailure, Downstream>
    private var value: ChildInput?
    private var subscription: Subscription?

    var hasValue: Bool { return value != nil }

    var upstream: Subscription? { return subscription }

    init(parent: CombineLatestInner<CombinedOutput, CombinedFailure, Downstream>) {
        self.parent = parent
    }

    func clearValue() {
        value = nil
    }

    /// The value this upstream has most recently sent, once the combination has been
    /// taken. `fatalError` rather than a trap message of our own: a combination that
    /// asks for a value that is not there is a bug in the operator, not a state a
    /// caller can reach.
    func takeValue() -> ChildInput {
        defer { value = nil }
        guard let value = value else { fatalError("CombineLatestChild: no value to take") }
        return value
    }

    func receive(subscription: Subscription) {
        self.subscription = subscription
        parent.childDidSubscribe(subscription)
    }

    func receive(_ input: ChildInput) -> Subscribers.Demand {
        value = input
        parent.childDidReceiveValue(self)
        return .none
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        parent.child(self, didReceive: completion)
    }
}

/// The subscription a `combineLatest` publisher hands downstream. It holds the most
/// recent value of each upstream and combines them as soon as every upstream has sent
/// one.
internal class CombineLatestInner<Output, Failure: Error, Downstream: Subscriber>: Subscription
    where Downstream.Input == Output, Downstream.Failure == Failure
{
    private let lock = UnfairLock.allocate()
    private let downstream: Downstream
    private var children: [any CombineLatestChildProtocol] = []
    private var remainingUpstreamCount: Int
    private var isDownstreamSubscribed = false
    private var downstreamDemand: Subscribers.Demand = .none
    private var isTerminated = false

    init(downstream: Downstream, upstreamCount: Int) {
        self.downstream = downstream
        self.remainingUpstreamCount = upstreamCount
    }

    /// Subscribes to one upstream through a child of its own, and returns the child so
    /// that the arity can read the value it holds when it combines.
    internal func connectChild<Upstream: Publisher>(_ upstream: Upstream)
        -> CombineLatestChild<Upstream.Output, Output, Failure, Downstream>
        where Upstream.Failure == Failure
    {
        let child = CombineLatestChild<Upstream.Output, Output, Failure, Downstream>(parent: self)
        children.append(child)
        upstream.subscribe(child)
        return child
    }

    deinit {
        lock.deallocate()
    }

    /// The combined value. Written out per arity, because the tuple is what the
    /// publisher's `Output` is.
    func combinedValue() -> Output {
        abstractMethod()
    }

    // MARK: Subscription

    func request(_ demand: Subscribers.Demand) {
        lock.lock()
        guard !isTerminated, demand > .none else {
            lock.unlock()
            return
        }
        downstreamDemand += demand
        let isSendable = isDownstreamSubscribed && hasCombinedValue
        lock.unlock()
        // A combination can only be sent once the downstream has asked for one. The
        // upstreams each hold a single value meanwhile, which is the buffer of one the
        // operator's documentation describes; nothing is lost while it waits.
        if isSendable {
            sendCombinedValueIfPossible()
        }
    }

    func cancel() {
        lock.lock()
        guard !isTerminated else {
            lock.unlock()
            return
        }
        isTerminated = true
        let subscriptions = children.compactMap { $0.upstream }
        lock.unlock()
        for subscription in subscriptions {
            subscription.cancel()
        }
    }

    // MARK: The children

    fileprivate func childDidSubscribe(_ subscription: Subscription) {
        lock.lock()
        guard !isTerminated else {
            lock.unlock()
            subscription.cancel()
            return
        }
        remainingUpstreamCount -= 1
        guard remainingUpstreamCount == 0 else {
            lock.unlock()
            return
        }
        isDownstreamSubscribed = true
        lock.unlock()
        downstream.receive(subscription: self)
        children.forEach { $0.upstream?.request(.max(1)) }
    }

    fileprivate func childDidReceiveValue(_ child: any CombineLatestChildProtocol) {
        lock.lock()
        guard !isTerminated, isDownstreamSubscribed, hasCombinedValue, downstreamDemand > .none else {
            lock.unlock()
            return
        }
        lock.unlock()
        sendCombinedValueIfPossible()
    }

    fileprivate func child(_ child: any CombineLatestChildProtocol,
                           didReceive completion: Subscribers.Completion<Failure>) {
        lock.lock()
        switch completion {
        case .failure(let error):
            guard !isTerminated else {
                lock.unlock()
                return
            }
            isTerminated = true
            let subscriptions = children.compactMap { $0.upstream }
            lock.unlock()
            for subscription in subscriptions {
                subscription.cancel()
            }
            downstream.receive(completion: .failure(error))
        case .finished:
            remainingUpstreamCount -= 1
            guard !isTerminated, remainingUpstreamCount > 0 else {
                isTerminated = true
                lock.unlock()
                downstream.receive(completion: .finished)
                return
            }
            lock.unlock()
        }
    }

    private var hasCombinedValue: Bool {
        return children.allSatisfy { $0.hasValue }
    }

    private func sendCombinedValueIfPossible() {
        lock.lock()
        guard !isTerminated, isDownstreamSubscribed,
              downstreamDemand > .none, hasCombinedValue else {
            lock.unlock()
            return
        }
        let value = combinedValue()
        downstreamDemand -= 1
        let children = self.children
        lock.unlock()
        let additionalDemand = downstream.receive(value)
        lock.lock()
        downstreamDemand += additionalDemand
        let isStillActive = !isTerminated
        lock.unlock()
        guard isStillActive else { return }
        // Every upstream's value was consumed by the combination just sent, so each of
        // them is asked for one more.
        children.forEach { $0.upstream?.request(.max(1)) }
    }
}
