//
//  Publishers.CollectByTime.swift
//
//  `Publishers.TimeGroupingStrategy`, `Publishers.CollectByTime` and the
//  `collect(_:options:)` operator: elements collected over an interval of a scheduler's
//  time, and sent on a schedule instead of one by one.
//

extension Publishers {

    /// A strategy for collecting received elements.
    public enum TimeGroupingStrategy<Context: Scheduler> {

        /// A grouping that collects and periodically publishes items.
        case byTime(Context, Context.SchedulerTimeType.Stride)

        /// A grouping that collects and publishes items periodically or when a buffer
        /// reaches a maximum size.
        case byTimeOrCount(Context, Context.SchedulerTimeType.Stride, Int)
    }

    /// A publisher that buffers and periodically publishes its items.
    public struct CollectByTime<Upstream: Publisher, Context: Scheduler>: Publisher {

        /// The kind of values published by this publisher.
        public typealias Output = [Upstream.Output]

        /// The kind of errors this publisher might publish.
        ///
        /// Use `Never` if this `Publisher` does not publish errors.
        public typealias Failure = Upstream.Failure

        /// The publisher that this publisher receives elements from.
        public let upstream: Upstream

        /// The strategy with which to collect and publish elements.
        public let strategy: Publishers.TimeGroupingStrategy<Context>

        /// `Scheduler` options to use for the strategy.
        public let options: Context.SchedulerOptions?

        public init(upstream: Upstream,
                    strategy: Publishers.TimeGroupingStrategy<Context>,
                    options: Context.SchedulerOptions?)
        {
            self.upstream = upstream
            self.strategy = strategy
            self.options = options
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where Upstream.Failure == Downstream.Failure, Downstream.Input == [Upstream.Output]
        {
            upstream.subscribe(Inner(downstream: subscriber, strategy: strategy, options: options))
        }
    }
}

extension Publisher {

    /// Collects elements by a given time-grouping strategy, and emits a single array of
    /// the collection.
    ///
    /// Use `collect(_:options:)` to emit arrays of elements on a schedule specified by a
    /// `Scheduler` and `Stride` that you provide. At the end of each scheduled interval,
    /// the publisher sends an array that contains the items it collected. If the
    /// upstream publisher finishes before filling the buffer, the publisher sends an
    /// array that contains the items it received.
    ///
    /// If the upstream publisher fails with an error, this publisher forwards the error
    /// to the downstream receiver instead of sending its output.
    ///
    /// - Parameters:
    ///   - strategy: The timing group strategy used by the operator to collect and
    ///     publish elements.
    ///   - options: `Scheduler` options to use for the strategy.
    /// - Returns: A publisher that collects elements by a given strategy, and emits
    ///   a single array of the collection.
    public func collect<S: Scheduler>(_ strategy: Publishers.TimeGroupingStrategy<S>,
                                      options: S.SchedulerOptions? = nil)
        -> Publishers.CollectByTime<Self, S>
    {
        return Publishers.CollectByTime(upstream: self, strategy: strategy, options: options)
    }
}

extension Publishers.CollectByTime {
    internal final class Inner<Downstream: Subscriber>: Subscriber, Subscription
        where Downstream.Input == [Upstream.Output], Downstream.Failure == Upstream.Failure
    {
        typealias Input = Upstream.Output

        typealias Failure = Upstream.Failure

        private let lock = UnfairLock.allocate()
        private let downstream: Downstream
        private let scheduler: Context
        private let stride: Context.SchedulerTimeType.Stride
        private let countLimit: Int?
        private let options: Context.SchedulerOptions?

        private var state = SubscriptionStatus.awaitingSubscription
        private var buffer: [Input] = []
        private var scheduled: Cancellable?
        private var downstreamDemand: Subscribers.Demand = .none

        init(downstream: Downstream,
             strategy: Publishers.TimeGroupingStrategy<Context>,
             options: Context.SchedulerOptions?)
        {
            self.downstream = downstream
            switch strategy {
            case .byTime(let scheduler, let stride):
                self.scheduler = scheduler
                self.stride = stride
                self.countLimit = nil
            case .byTimeOrCount(let scheduler, let stride, let count):
                self.scheduler = scheduler
                self.stride = stride
                self.countLimit = count
            }
            self.options = options
        }

        deinit {
            lock.deallocate()
        }

        func receive(subscription: Subscription) {
            lock.lock()
            guard case .awaitingSubscription = state else {
                lock.unlock()
                subscription.cancel()
                return
            }
            state = .subscribed(subscription)
            lock.unlock()
            downstream.receive(subscription: self)
        }

        func receive(_ input: Input) -> Subscribers.Demand {
            lock.lock()
            guard case .subscribed = state else {
                lock.unlock()
                return .none
            }
            buffer.append(input)
            let isFull = countLimit.map { buffer.count >= $0 } ?? false
            lock.unlock()
            if isFull {
                send()
            }
            return .none
        }

        func receive(completion: Subscribers.Completion<Failure>) {
            lock.lock()
            guard case .subscribed = state else {
                lock.unlock()
                return
            }
            state = .terminal
            scheduled?.cancel()
            scheduled = nil
            let values = buffer
            buffer = []
            let isSendable = downstreamDemand > .none && !values.isEmpty
            lock.unlock()
            // What was collected before the upstream finished is sent first, and the
            // completion after it, in the order a subscriber sees them. A collection the
            // downstream never asked for is not sent; the completion is not withheld
            // for it, because a subscriber is entitled to the end of the stream.
            if isSendable {
                downstreamDemand -= 1
                let additionalDemand = downstream.receive(values)
                if additionalDemand > .none {
                    lock.lock()
                    downstreamDemand += additionalDemand
                    lock.unlock()
                }
            }
            downstream.receive(completion: completion)
        }

        func request(_ demand: Subscribers.Demand) {
            lock.lock()
            guard case .subscribed = state else {
                lock.unlock()
                return
            }
            downstreamDemand += demand
            let isSendable = downstreamDemand > .none && !buffer.isEmpty
            lock.unlock()
            if isSendable {
                send()
            }
        }

        func cancel() {
            lock.lock()
            guard case .subscribed(let subscription) = state else {
                lock.unlock()
                return
            }
            state = .terminal
            scheduled?.cancel()
            scheduled = nil
            buffer = []
            lock.unlock()
            subscription.cancel()
        }

        /// Schedules the next tick, and sends what has been collected if the downstream
        /// has asked for it. Called once per subscription and once per collection, so
        /// that the schedule keeps running for as long as the publisher is subscribed.
        private func send() {
            lock.lock()
            guard case .subscribed = state else {
                lock.unlock()
                return
            }
            scheduled?.cancel()
            scheduled = scheduler.schedule(after: scheduler.now.advanced(by: stride),
                                           interval: stride,
                                           tolerance: scheduler.minimumTolerance,
                                           options: options) { [weak self] in
                self?.tick()
            }
            let isSendable = downstreamDemand > .none && !buffer.isEmpty
            guard isSendable else {
                lock.unlock()
                return
            }
            let values = buffer
            buffer = []
            downstreamDemand -= 1
            lock.unlock()
            let additionalDemand = downstream.receive(values)
            if additionalDemand > .none {
                lock.lock()
                downstreamDemand += additionalDemand
                let isSendableAgain = !buffer.isEmpty && downstreamDemand > .none
                lock.unlock()
                if isSendableAgain {
                    send()
                }
            }
        }

        /// One scheduled interval. The tick only sends; the schedule itself is the
        /// repeating one installed by `send()`, so nothing has to be re-armed here.
        private func tick() {
            send()
        }
    }
}
