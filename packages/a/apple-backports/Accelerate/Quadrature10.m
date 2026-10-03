// quadrature_integrate, iOS 10.0: the one entry point of vecLib/Quadrature/Integration.h.
//
// The header says what the three integrators are: "The QNG (simple non-adaptive Gauss-Kronrod integration)
// and QAG (simple adaptive Gauss-Kronrod integration) integrators are C ports of the QUADPACK library
// corresponding routines. The QAGS integrator provides the functionality offered by the QAGS and QAGI
// QUADPACK routines." So the port's answer has to be QUADPACK's algorithms and QUADPACK's node tables, and
// this is a C translation of them, not an adaptive integrator of our own: the numbers only agree if the
// rules, the subdivision order and the epsilon extrapolation are the same.
//
// **What was read, and where from.** The QUADPACK originals from netlib, fetched for this file and not
// from a package cache: quadpack/dqng.f, dqagse.f, dqagie.f, dqk15.f, dqk15i.f, dqk21.f, dqk31.f, dqk41.f,
// dqk51.f, dqk61.f, dqelg.f, dqpsrt.f, dqresc.f (2 546 lines). QUADPACK is public domain. The two drivers
// and the six rules are translated statement for statement; the table below is generated from the DATA
// statements of those files rather than typed, so a digit cannot be mistyped on the way.
//
// **Measured against the host, which is a full oracle here.** `vecLib/Quadrature/Quadrature.h` includes
// `Integration.h`, so the umbrella carries the declaration and the 16.4 SDK this package builds against has
// the whole of it. Every mapping below was measured on the host's own function and is written down where it
// is used; the two that are not QUADPACK's own are the options' spelling and the status codes:
//
//   - `qag_points_per_interval` takes 0, 15, 21, 31, 41, 51 and 61, and 0 is the 21-point rule - measured by
//     the number of points the caller's callback sees, 63 for 21, 105 for 15 and 61 for 61 on the same
//     integral. Anything else (10, 20, 100 measured) answers 0 with QUADRATURE_INVALID_ARG_ERROR.
//   - `max_intervals` is the subdivision limit, and a workspace overrides it: the limit is
//     `workspace_size / QUADRATURE_INTEGRATE_QAG_WORKSPACE_PER_INTERVAL` for QAG and the same over 152 bytes
//     for QAGS, and a workspace too small for one interval answers QUADRATURE_INVALID_ARG_ERROR (measured at
//     31 bytes for QAG and 100 for QAGS, against 32 and 152 for one interval). Without a workspace a
//     `max_intervals` of zero is the same refusal, and QNG ignores the field entirely.
//   - QUADPACK's `ier` is mapped to the header's codes: 0 to QUADRATURE_SUCCESS, 6 to
//     QUADRATURE_INVALID_ARG_ERROR (a zero absolute tolerance with a relative one below 50 * DBL_EPSILON -
//     measured: both tolerances zero answers 0 with status -2), 1 and 5 to
//     QUADRATURE_INTEGRATE_MAX_EVAL_ERROR (-101) and 2, 3 and 4 to
//     QUADRATURE_INTEGRATE_BAD_BEHAVIOUR_ERROR (-102). Measured at 1e-300 tolerances: QNG and QAGS answer
//     -101 and QAG answers -102.
//   - An `integrator` the enumeration does not name answers 0 with QUADRATURE_ERROR (-1) and leaves
//     `abs_error` untouched (measured: 3 and -1, with the caller's -1 still there).
//   - A bound of a wrong infinity is a refusal: QNG over an infinite bound answers
//     QUADRATURE_INVALID_ARG_ERROR, and only QAGS takes one, which is the header's "If the integrator is
//     QAGS, one or both of the interval bounds can be infinite".
//
// **The callback is called the way the host calls it**: one call per rule pass, with every abscissa of that
// pass in one array. Measured on the host for the same integral: QAG makes one call of 21, 15 or 61 points
// per pass, and QNG makes a call of 21 and then one of 22 - the 43-point rule reuses the 21 the first pass
// already had and asks only for the 22 it does not, which is what dqng's `savfun` is for.
//
// This is alone in its file because the two names are 10.0 and nothing else in the package is: measured from
// the release's armv7 caches, 10.0 is the first held release that exports quadrature_integrate, so an object
// carrying it beside a 9.0 or a 15.0 symbol would hold two releases and the gate refuses that.

#import <Accelerate/Accelerate.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wnonnull"

// The three machine constants d1mach answers, named as dqng and dqk21 name them.
#define CHARON_EPMACH 2.2204460492503131e-16
#define CHARON_UFLOW 2.2250738585072014e-308
#define CHARON_OFLOW 1.7976931348623157e+308

    // The Gauss-Kronrod-Patterson abscissae and weights of dqng.f: x1 is common to the 10-, 21-, 43-
    // and 87-point rules, x2 to the 21-, 43- and 87-point ones, x3 to the 43- and 87-point ones and x4 is
    // the 87-point rule's own. L. W. Fullerton calculated them with 101-digit arithmetic in 1981.
static const double x1[5] = {
    9.73906528517171743430935748619959e-01, 8.65063366688984536345685683045303e-01, 6.79409568299024435589217318920419e-01,
    4.33395394129247213399480642692652e-01, 1.48874338981631215705903059642878e-01,
};
static const double x2[5] = {
    9.95657163025808089606982775876531e-01, 9.30157491355708243574440530210268e-01, 7.80817726586416904765997060167138e-01,
    5.62757134668604663829682976938784e-01, 2.94392862701460200636205399860046e-01,
};
static const double x3[11] = {
    9.99333360901932032938077554717893e-01, 9.87433402908088897476091005955823e-01, 9.54807934814266290324269448319683e-01,
    9.00148695748328342425281789473956e-01, 8.25198314983114133980279802926816e-01, 7.32148388989305010099428727698978e-01,
    6.22847970537725226236602793505881e-01, 4.99479574071056475759178283624351e-01, 3.64901661346580752365298394579440e-01,
    2.22254919776601306269370184054424e-01, 7.46506174613833228814741005407996e-02,
};
static const double x4[22] = {
    9.99902977262729253382644856174011e-01, 9.97989895986678754447041228559101e-01, 9.92175497860687261031387151888339e-01,
    9.81358163572712771660633279680042e-01, 9.65057623858384672210775079292944e-01, 9.43167613133670590386259391380008e-01,
    9.15806414685507164108457800466567e-01, 8.83221657771316448481968564010458e-01, 8.45710748462415673465386589668924e-01,
    8.03557658035230937265680495329434e-01, 7.57005730685495592524603125639260e-01, 7.06273209787321776254032101860503e-01,
    6.51589466501177883017703607038129e-01, 5.93223374057961105876302099204622e-01, 5.31493605970831950457977654878050e-01,
    4.66763623042022846032494953760761e-01, 3.99424847859218778989287557124044e-01, 3.29874877106188291175925542120240e-01,
    2.58503559202161559138488655662513e-01, 1.85695396568346660082227117527509e-01, 1.11842213179907473685759100590076e-01,
    3.73521233946198724651388545225927e-02,
};
static const double w10[5] = {
    6.66713443086881379917585377370415e-02, 1.49451349150580586888636958065035e-01, 2.19086362515982041587747630728700e-01,
    2.69266719309996349629443557205377e-01, 2.95524224714752870024625508449390e-01,
};
static const double w21a[5] = {
    3.25581623079647247687162803231331e-02, 7.50396748109199568377292166587722e-02, 1.09387158802297643211964839338179e-01,
    1.34709217311473339329097598238150e-01, 1.47739104901338486053319343227486e-01,
};
static const double w21b[6] = {
    1.16946388673718742329254993705945e-02, 5.47558965743519948654594031722809e-02, 9.31254545836976005412921608694887e-02,
    1.23491976262065844549553617071069e-01, 1.42775938577060085288294999372738e-01, 1.49445554002916897173847132762603e-01,
};
static const double w43a[10] = {
    1.62967342896665652596244200367437e-02, 3.75228761208694985840317315251013e-02, 5.46949020582554387703844156476407e-02,
    6.73554146094780814557623216387583e-02, 7.38701996323939541477798798041476e-02, 5.76855605976979608773280716604859e-03,
    2.73718905932488418275561059544998e-02, 4.65608269104288291506676955577859e-02, 6.17449952014425679225340104494535e-02,
    7.13872672686933912311602057343407e-02,
};
static const double w43b[12] = {
    1.84447764021241408100015846116548e-03, 1.07986895858916513712966178673014e-02, 2.18953638677954268154657313516509e-02,
    3.25974639753456862933944648830220e-02, 4.21631379351918092468487486712547e-02, 5.07419396001845754429204760072025e-02,
    5.83793955426192487379033480010548e-02, 6.47464049514458878098466243500297e-02, 6.95661979123564783167310565659136e-02,
    7.28244414718332150338042652037984e-02, 7.45077510141751164773893378878711e-02, 7.47221475174030119736912070038670e-02,
};
static const double w87a[21] = {
    8.14837738414917259199832244576100e-03, 1.87614382015628237965199076597855e-02, 2.73474510500522870193318425435791e-02,
    3.36777073116379319084323640254297e-02, 3.69350998204279051817522372402891e-02, 2.88487243021153059313599342772250e-03,
    1.36859460227127024273263700138159e-02, 2.32804135028883106561803373324437e-02, 3.08724976117133592667940433784679e-02,
    3.56936336394187703202618422437808e-02, 9.15283345202241383278818354085615e-04, 5.39928021930047123688733989865796e-03,
    1.09476796011189307644695389853950e-02, 1.62987316967873364925711854311885e-02, 2.10815688892038340107593086258930e-02,
    2.53709697692538274638174300434912e-02, 2.91896977564757541256934558759895e-02, 3.23732024672027871026180889657553e-02,
    3.47830989503651460958977281734406e-02, 3.64122207313517867732777233413799e-02, 3.72538755030477064522642649535555e-02,
};
static const double w87b[23] = {
    2.74145563762072342825493187490338e-04, 1.80712415505794284434348817569571e-03, 4.09686928275916455166605345539210e-03,
    6.75829005184737895139956975754103e-03, 9.54995767220164631927659115717688e-03, 1.23294476522448539362875052916024e-02,
    1.50104473463889519224689905740888e-02, 1.75489679862431899315389216553740e-02, 1.99380377864408868393564233656434e-02,
    2.21949359610122860797520871756205e-02, 2.43391471260008054877665983894985e-02, 2.63745054148392076009965734328944e-02,
    2.82869107887711995763524441827030e-02, 3.00525811280926945234792668770751e-02, 3.16467513714399281687938980667241e-02,
    3.30504134199785040704178129544744e-02, 3.42550997042260635394583800916735e-02, 3.52624126601566792449382603535923e-02,
    3.60769896228887027023191080843389e-02, 3.66986044984560916271121300269442e-02, 3.71205492698325756339983172438224e-02,
    3.73342287519350390923023041978013e-02, 3.73610737626790256893372088597971e-02,
};

    // The 15-point Gauss-Kronrod rule of dqk15.f, in the order its DATA statements give: xgk
    // holds the 8 abscissae from the outermost pair down to the centre, wgk the 8 weights that
    // multiply them, and wg the 3 Gauss weights for the pairs and wg[3] the centre point's own. The weight at
    // wgk[j] multiplies the pair at abscissa xgk[j]; the Gauss pairs are the odd j.
static const double k15_wg[4] = {
    1.29484966168869702896060402963485e-01, 2.79705391489276644634287549706642e-01, 3.81830050505118923087621851664153e-01,
    4.17959183673469403252909160073614e-01,
};
static const double k15_wgk[8] = {
    2.29353220105292243680139563366538e-02, 6.30920926299785578272860675497213e-02, 1.04790010322250187746462302129657e-01,
    1.40653259715525918993606069307134e-01, 1.69004726639267910393016336456640e-01, 1.90350578064785419529769683322229e-01,
    2.04432940075298885673760196368676e-01, 2.09482141084727818691746392687492e-01,
};
static const double k15_xgk[8] = {
    9.91455371120812611884787202143343e-01, 9.49107912342758486268223805382149e-01, 8.64864423359769096677496236225124e-01,
    7.41531185599394460083999547350686e-01, 5.86087235467691147761115644243546e-01, 4.05845151377397184155881859624060e-01,
    2.07784955007898480827677190063696e-01, 0.00000000000000000000000000000000e+00,
};

    // The 21-point Gauss-Kronrod rule of dqk21.f, in the order its DATA statements give: xgk
    // holds the 11 abscissae from the outermost pair down to the centre, wgk the 11 weights that
    // multiply them, and wg the 5 Gauss weights for the pairs and none for the centre. The weight at
    // wgk[j] multiplies the pair at abscissa xgk[j]; the Gauss pairs are the odd j.
static const double k21_wg[5] = {
    6.66713443086881379917585377370415e-02, 1.49451349150580586888636958065035e-01, 2.19086362515982041587747630728700e-01,
    2.69266719309996349629443557205377e-01, 2.95524224714752870024625508449390e-01,
};
static const double k21_wgk[11] = {
    1.16946388673718742329254993705945e-02, 3.25581623079647247687162803231331e-02, 5.47558965743519948654594031722809e-02,
    7.50396748109199568377292166587722e-02, 9.31254545836976005412921608694887e-02, 1.09387158802297643211964839338179e-01,
    1.23491976262065844549553617071069e-01, 1.34709217311473339329097598238150e-01, 1.42775938577060085288294999372738e-01,
    1.47739104901338486053319343227486e-01, 1.49445554002916897173847132762603e-01,
};
static const double k21_xgk[11] = {
    9.95657163025808089606982775876531e-01, 9.73906528517171743430935748619959e-01, 9.30157491355708243574440530210268e-01,
    8.65063366688984536345685683045303e-01, 7.80817726586416904765997060167138e-01, 6.79409568299024435589217318920419e-01,
    5.62757134668604663829682976938784e-01, 4.33395394129247213399480642692652e-01, 2.94392862701460200636205399860046e-01,
    1.48874338981631215705903059642878e-01, 0.00000000000000000000000000000000e+00,
};

    // The 31-point Gauss-Kronrod rule of dqk31.f, in the order its DATA statements give: xgk
    // holds the 16 abscissae from the outermost pair down to the centre, wgk the 16 weights that
    // multiply them, and wg the 7 Gauss weights for the pairs and wg[7] the centre point's own. The weight at
    // wgk[j] multiplies the pair at abscissa xgk[j]; the Gauss pairs are the odd j.
static const double k31_wg[8] = {
    3.07532419961172691358353148416427e-02, 7.03660474881081243747615872052847e-02, 1.07159220467171939494832599848451e-01,
    1.39570677926154324000052042720199e-01, 1.66269205816993920210578039586835e-01, 1.86161000015562211329367414691660e-01,
    1.98431485327111578609304842757410e-01, 2.02578241925561286507218028418720e-01,
};
static const double k31_wgk[16] = {
    5.37747987292334916897829089066363e-03, 1.50079473293161218955260594043466e-02, 2.54608473267153197217016469267037e-02,
    3.53463607913758470768783581661410e-02, 4.45897513247648785705834484360821e-02, 5.34815246909280880838188920733955e-02,
    6.20095678006706424456595527772151e-02, 6.98541213187282572505409916630015e-02, 7.68496807577203761008277638211439e-02,
    8.30805028231330205956695067470719e-02, 8.85644430562117640493013936975331e-02, 9.31265981708253171023059735489369e-02,
    9.66427269836236807476481658341072e-02, 9.91735987217919612302097220890573e-02, 1.00769845523875592463447503632779e-01,
    1.01330007014791542707676796908345e-01,
};
static const double k31_xgk[16] = {
    9.98002298693397071893684824317461e-01, 9.87992518020485377405748295132071e-01, 9.67739075679139082453161790908780e-01,
    9.37273392400705951388317771488801e-01, 8.97264532344081877646146949700778e-01, 8.48206583410427206182191639527446e-01,
    7.90418501442465948336746350832982e-01, 7.24417731360170069621062793885358e-01, 6.50996741297417025329252737719798e-01,
    5.70972172608538830473889902350493e-01, 4.85081863640239696611189401664888e-01, 3.94151347077563385390419625764480e-01,
    2.99180007153168836531165197811788e-01, 2.01194093997434514387023796189169e-01, 1.01142066918717493662072115512274e-01,
    0.00000000000000000000000000000000e+00,
};

    // The 41-point Gauss-Kronrod rule of dqk41.f, in the order its DATA statements give: xgk
    // holds the 21 abscissae from the outermost pair down to the centre, wgk the 21 weights that
    // multiply them, and wg the 10 Gauss weights for the pairs and none for the centre. The weight at
    // wgk[j] multiplies the pair at abscissa xgk[j]; the Gauss pairs are the odd j.
static const double k41_wg[10] = {
    1.76140071391521178811867542890468e-02, 4.06014298003869386621822457072994e-02, 6.26720483341090678353069165495981e-02,
    8.32767415767047547436874310733401e-02, 1.01930119817240441570938003224001e-01, 1.18194531961518412011002965300577e-01,
    1.31688638449176637079673923835799e-01, 1.42096109318382041175610197569767e-01, 1.49172986472603741336939719985821e-01,
    1.52753387130725837295130986603908e-01,
};
static const double k41_wgk[21] = {
    3.07358371852053165879103957536245e-03, 8.60026985564294257913253716196778e-03, 1.46261692569712529327086159014470e-02,
    2.03883734612665228069783296405149e-02, 2.58821336049511602217521044622117e-02, 3.12873067770328000536395052222360e-02,
    3.66001697582007956555116834351793e-02, 4.16688733279736850390051472459163e-02, 4.64348218674976720432567844909499e-02,
    5.09445739237286907008517289341398e-02, 5.51951053482859915755298629846948e-02, 5.91114008806395696549174090250744e-02,
    6.26532375547811659632913006134913e-02, 6.58345971336184165867422279916354e-02, 6.86486729285216146223547184490599e-02,
    7.10544235534440737911410224114661e-02, 7.30306903327866685504687893626397e-02, 7.45828754004991822945669355249265e-02,
    7.57044976845566708334445138461888e-02, 7.63778676720807403466295681937481e-02, 7.66007119179996504021445957732794e-02,
};
static const double k41_xgk[21] = {
    9.98859031588277712643275663140230e-01, 9.93128599185094884660429670475423e-01, 9.81507877450250254547370332147693e-01,
    9.63971927277913809284370927343844e-01, 9.40822633831754795430413196299924e-01, 9.12234428251325946135352751298342e-01,
    8.78276811252281963682264631643193e-01, 8.39116971822218782328661745850695e-01, 7.95041428837551245045744963135803e-01,
    7.46331906460150795723507144430187e-01, 6.93237656334751428666152150981361e-01, 6.36053680726515024979050849651685e-01,
    5.75140446819710327019947726512328e-01, 5.10867001950827126499632413469953e-01, 4.43593175238725101472425649262732e-01,
    3.73706088715419548762497470306698e-01, 3.01627868114912989216946925807861e-01, 2.27785851141645068196339707355946e-01,
    1.52605465240922666403378116228851e-01, 7.65265211334973383117130651953630e-02, 0.00000000000000000000000000000000e+00,
};

    // The 51-point Gauss-Kronrod rule of dqk51.f, in the order its DATA statements give: xgk
    // holds the 26 abscissae from the outermost pair down to the centre, wgk the 26 weights that
    // multiply them, and wg the 12 Gauss weights for the pairs and wg[12] the centre point's own. The weight at
    // wgk[j] multiplies the pair at abscissa xgk[j]; the Gauss pairs are the odd j.
static const double k51_wg[13] = {
    1.13937985010262882862308586595645e-02, 2.63549866150321367153086526968764e-02, 4.09391567013063159552466174773144e-02,
    5.49046959758351937885834104235983e-02, 6.80383338123569103572663152590394e-02, 8.01407003350010221920385333760350e-02,
    9.10282619829636541197714905138128e-02, 1.00535949067050642269371962811420e-01, 1.08519624474263651214833714675478e-01,
    1.14858259145711641413534209732461e-01, 1.19455763535784770246195307663584e-01, 1.22242442990310035133560973008571e-01,
    1.23176053726715445391093339821964e-01,
};
static const double k51_wgk[26] = {
    1.98738389233031609304447329122922e-03, 5.56193213535671401870352781315887e-03, 9.47397338617415180062053536858002e-03,
    1.32362291955716755709193677148505e-02, 1.68478177091282987909437451889971e-02, 2.04353711458828343761062740213674e-02,
    2.40099456069532146695877372621908e-02, 2.74753175878517386099275654487428e-02, 3.07923001673874874306591209460748e-02,
    3.40021302743293354908793446611526e-02, 3.71162714834155429977080586922966e-02, 4.00838255040323818145786560762645e-02,
    4.28728450201700528321424599198508e-02, 4.55029130499217879246565132689284e-02, 4.79825371388367116765039099846035e-02,
    5.02776790807156689910861757653038e-02, 5.23628858064074734213200201793370e-02, 5.42511298885454892881874400245579e-02,
    5.59508112204123164712399329800974e-02, 5.74371163615678345659709691517492e-02, 5.86896800223942055607651013815484e-02,
    5.97203403241740593543340764881577e-02, 6.05394553760458600799587713936489e-02, 6.11285097170530464238957790712448e-02,
    6.14711898714253163200638141461241e-02, 6.15808180678329361579237399837439e-02,
};
static const double k51_xgk[26] = {
    9.99262104992609812015302850340959e-01, 9.95556969790498125227884429477854e-01, 9.88035794534077194128940391237848e-01,
    9.76663921459517525569538065610686e-01, 9.61614986425842532824503905430902e-01, 9.42974571228974323133797952323221e-01,
    9.20747115281701611344544744497398e-01, 8.94991997878275324929120415617945e-01, 8.65847065293275597319677672203397e-01,
    8.33442628760833970069654696999351e-01, 7.97873797998500111638975340611069e-01, 7.59259263037357579051445100049023e-01,
    7.17766406813084345550635134713957e-01, 6.73566368473468402022774625947932e-01, 6.26810099010317367529410148563329e-01,
    5.77662930241222949412360776477726e-01, 5.26325284334719145640235637984006e-01, 4.73002731445714974523042428700137e-01,
    4.17885382193037724363193774479441e-01, 3.61172305809387861330606028786860e-01, 3.03089538931107849162316369984183e-01,
    2.43866883720988442130206408364756e-01, 1.83718939421048887972176544280956e-01, 1.22864692610710396492024187864445e-01,
    6.15444830056850814004043570548674e-02, 0.00000000000000000000000000000000e+00,
};

    // The 61-point Gauss-Kronrod rule of dqk61.f, in the order its DATA statements give: xgk
    // holds the 31 abscissae from the outermost pair down to the centre, wgk the 31 weights that
    // multiply them, and wg the 15 Gauss weights for the pairs and none for the centre. The weight at
    // wgk[j] multiplies the pair at abscissa xgk[j]; the Gauss pairs are the odd j.
static const double k61_wg[15] = {
    7.96819249616660500723508420151120e-03, 1.84664683110909583207970285911870e-02, 2.87847078833233689654225173626401e-02,
    3.87991925696270500978357631538529e-02, 4.84026728305940526220219055630878e-02, 5.74931562176190652513341206031328e-02,
    6.59742298821804906694410419731867e-02, 7.37559747377052044026157773259911e-02, 8.07558952294202131438893843551341e-02,
    8.68997872010829758293581903672020e-02, 9.21225222377861224787309879502573e-02, 9.63687371746442533737564417606336e-02,
    9.95934205867952671020759680686751e-02, 1.01762389748405499001471241626859e-01, 1.02852652893558840774268503537314e-01,
};
static const double k61_wgk[31] = {
    1.38901369867700766498608277998983e-03, 3.89046112709988400890637194606825e-03, 6.63070391593129256080363376213427e-03,
    9.27327965951776390929328641732354e-03, 1.18230152534963411925517107192718e-02, 1.43697295070458041371663782115320e-02,
    1.69208891890532710233774338348667e-02, 1.94141411939423823296291260476210e-02, 2.18280358216091929790536596556194e-02,
    2.41911620780805997066309487308899e-02, 2.65099548823331011837556303589736e-02, 2.87540487650412915354714016302751e-02,
    3.09072575623877618400392464081960e-02, 3.29814470574837231842124651848280e-02, 3.49793380280600252341116629395401e-02,
    3.68823646518212297507055552614474e-02, 3.86789456247275953426623118502903e-02, 4.03745389515359556775742078116309e-02,
    4.19698102151642438162326698147808e-02, 4.34525397013560688019850886121276e-02, 4.48148001331626633092497513644048e-02,
    4.60592382710069900286775634867809e-02, 4.71855465692991513093623723307246e-02, 4.81858617570871325397341422558384e-02,
    4.90554345550297810074624749177019e-02, 4.97956834270742096371087370698660e-02, 5.04059214027823485060331165641401e-02,
    5.08817958987496099521052883574157e-02, 5.12215478492587736325525327174546e-02, 5.14261285374590232377656207063410e-02,
    5.14947294294515675594503534284740e-02,
};
static const double k61_xgk[31] = {
    9.99484410050490601484796115983045e-01, 9.96893484074649505188858711335342e-01, 9.91630996870404568532819666870637e-01,
    9.83668123279747175224940747284563e-01, 9.73116322501126229660428634815617e-01, 9.60021864968307547805181911826367e-01,
    9.44374444748560026852146620512940e-01, 9.26200047429274309074287430121331e-01, 9.05573307699907847911902081250446e-01,
    8.82560535792052736070445462246425e-01, 8.57205233546061151628236984834075e-01, 8.29565762382768356886231231328566e-01,
    7.99727835821839039276426319702296e-01, 7.67777432104826185188528597791446e-01, 7.33790062453226754612956028722692e-01,
    6.97850494793315845321046708704671e-01, 6.60061064126626906300998598453589e-01, 6.20526182989242891530068391148234e-01,
    5.79345235826361659725591835012892e-01, 5.36624148142019863350071773311356e-01, 4.92480467861778570259900789096719e-01,
    4.47033769538089154060855889838422e-01, 4.00401254830394404127247298674774e-01, 3.52704725530878115957733598406776e-01,
    3.04073202273625053937422535454971e-01, 2.54636926167889854344394962026854e-01, 2.04525116682309882065737838274799e-01,
    1.53869913608583541719809772985172e-01, 1.02806937966737024781060938494193e-01, 5.14718425553176983644476649715216e-02,
    0.00000000000000000000000000000000e+00,
};

// ---------------------------------------------------------------- the caller's integrand

// The header's callback is the array form, `fun(arg, n, x, y)`, and the drivers below ask for one rule's
// worth of abscissae at a time - which is one call, as the host makes it.
typedef void (*CharonIntegrand)(void *arg, size_t n, const double *x, double *y);

static void charon_call(CharonIntegrand fun, void *arg, const double *x, double *y, int n)
{
    fun(arg, (size_t)n, x, y);
}

// ---------------------------------------------------------------- one Gauss-Kronrod pass

// dqk15, dqk21, dqk31, dqk41, dqk51 and dqk61 are the same routine with three different tables, so they are
// one here. `n` is the Kronrod order; the Gauss weights cover the first (n + 1) / 2 of them.
typedef struct CharonRule {
    const double *wg;
    const double *wgk;
    const double *xgk;
    int n;            // the Kronrod order: xgk and wgk have this many
    int gauss_pairs;  // the Gauss weights that multiply a symmetric pair
    int gauss_centre; // 1 when the centre point carries a Gauss weight too, which the 15-point rule's does
} CharonRule;

static const CharonRule charon_k15 = {k15_wg, k15_wgk, k15_xgk, 15, 3, 1};
static const CharonRule charon_k21 = {k21_wg, k21_wgk, k21_xgk, 21, 5, 0};
static const CharonRule charon_k31 = {k31_wg, k31_wgk, k31_xgk, 31, 8, 0};
static const CharonRule charon_k41 = {k41_wg, k41_wgk, k41_xgk, 41, 10, 0};
static const CharonRule charon_k51 = {k51_wg, k51_wgk, k51_xgk, 51, 13, 0};
static const CharonRule charon_k61 = {k61_wg, k61_wgk, k61_xgk, 61, 15, 0};

static void charon_dqk(const CharonRule *rule, CharonIntegrand fun, void *arg, double a, double b, double *result,
                       double *abserr, double *resabs, double *defabs)
{
    double hlgth = 0.5 * (b - a);
    double centr = 0.5 * (b + a);
    double dhlgth = fabs(hlgth);
    const int n = rule->n;
    const int centre = (n - 1) / 2;   // the Kronrod rule's own centre abscissa, 0 based
    const int pairs = (n - 1) / 2;     // the symmetric pairs, which is every other point
    double fv1[32], fv2[32];
    double resg = 0.0, resk, resabs_value, resasc, reskh, fsum, absc;
    double *x = (double *)malloc(sizeof(double) * (size_t)n);
    double *y = (double *)malloc(sizeof(double) * (size_t)n);
    if (!x || !y) {
        free(x);
        free(y);
        *result = 0.0;
        *abserr = 0.0;
        if (resabs) {
            *resabs = 0.0;
        }
        if (defabs) {
            *defabs = 0.0;
        }
        return;
    }
    // The n abscissae, in the table's own order, and one call for all of them - which is what the host makes
    // (measured: one call of 21, 15 or 61 points per pass).
    // Pair p is the two points 2p and 2p+1 at the table's own abscissa p, and the centre is its own point:
    // the tables run from the largest abscissa down to the centre, which is dqk21's own layout.
    for (int p = 0; p < centre; p++) {
        absc = hlgth * rule->xgk[p];
        x[2 * p] = centr - absc;
        x[2 * p + 1] = centr + absc;
    }
    x[centre] = centr;
    charon_call(fun, arg, x, y, n);
    resk = rule->wgk[centre] * y[centre];
    resabs_value = fabs(resk);
    if (rule->gauss_centre) {
        resg = rule->wg[rule->gauss_pairs] * y[centre];
    }
    // The pairs the Gauss rule takes, which are the first ones, so resg is the 10-, 7- or 15-point answer.
    for (int j = 0; j < rule->gauss_pairs; j++) {
        double fval1 = y[2 * j], fval2 = y[2 * j + 1];
        fv1[j] = fval1;
        fv2[j] = fval2;
        fsum = fval1 + fval2;
        resg += rule->wg[j] * fsum;
        resk += rule->wgk[2 * j] * fsum;
        resabs_value += rule->wgk[2 * j] * (fabs(fval1) + fabs(fval2));
    }
    // And every point the Gauss rule does not take, which only the Kronrod rule needs.
    for (int p = rule->gauss_pairs; p < pairs; p++) {
        resk += rule->wgk[p] * (y[2 * p] + y[2 * p + 1]);
        resabs_value += rule->wgk[p] * (fabs(y[2 * p]) + fabs(y[2 * p + 1]));
    }
    reskh = resk * 0.5;
    resasc = rule->wgk[centre] * fabs(y[centre] - reskh);
    for (int j = 0; j < pairs; j++) {
        resasc += rule->wgk[j] * (fabs(fv1[j] - reskh) + fabs(fv2[j] - reskh));
    }
    *result = resk * hlgth;
    resabs_value *= dhlgth;
    resasc *= dhlgth;
    *abserr = fabs((resk - resg) * hlgth);
    if (resasc != 0.0 && *abserr != 0.0) {
        *abserr = resasc * fmin(1.0, pow(200.0 * (*abserr) / resasc, 1.5));
    }
    if (resabs_value > CHARON_UFLOW / (50.0 * CHARON_EPMACH)) {
        *abserr = fmax((CHARON_EPMACH * 50.0) * resabs_value, *abserr);
    }
    if (resabs) {
        *resabs = resabs_value;
    }
    if (defabs) {
        *defabs = resabs_value;
    }
    free(x);
    free(y);
}

// ---------------------------------------------------------------- QNG, the non-adaptive rule

// dqng: the 10-, 21-, 43- and 87-point rules over the whole interval, escalating until the error is inside
// the tolerance. `savfun` is the array of sums already computed, which is what makes the 43- and 87-point
// passes ask only for the points the 21-point one did not - and what the host's own call sizes show it doing
// (21 then 22, measured).
static int charon_dqng(CharonIntegrand fun, void *arg, double a, double b, double epsabs, double epsrel,
                       double *result, double *abserr, int *neval)
{
    double savfun[87], fv1[5], fv2[5], fv3[5], fv4[5];
    double x[22], y[22];
    double hlgth = 0.5 * (b - a);
    double dhlgth = fabs(hlgth);
    double centr = 0.5 * (b + a);
    double fcentr, absc, fval1, fval2, fval;
    double res10, res21, res43, res87, resabs, resasc, reskh;
    int ipx, ier = 1;
    *result = 0.0;
    *abserr = 0.0;
    *neval = 0;
    if (epsabs <= 0.0 && epsrel < fmax(50.0 * CHARON_EPMACH, 0.5e-28)) {
        return 6;
    }
    x[0] = centr;
    y[0] = 0.0;
    charon_call(fun, arg, x, y, 1);
    fcentr = y[0];
    *neval = 21;
    for (int pass = 1; pass <= 3; pass++) {
        if (pass == 1) {
            res10 = 0.0;
            res21 = x1[4] * 0 + w21b[5] * fcentr;
            resabs = w21b[5] * fabs(fcentr);
            for (int k = 0; k < 5; k++) {
                absc = hlgth * x1[k];
                x[2 * k] = centr + absc;
                x[2 * k + 1] = centr - absc;
            }
            charon_call(fun, arg, x, y, 10);
            for (int k = 0; k < 5; k++) {
                fval1 = y[2 * k];
                fval2 = y[2 * k + 1];
                fval = fval1 + fval2;
                res10 += w10[k] * fval;
                res21 += w21a[k] * fval;
                resabs += w21a[k] * (fabs(fval1) + fabs(fval2));
                savfun[k] = fval;
                fv1[k] = fval1;
                fv2[k] = fval2;
            }
            ipx = 5;
            for (int k = 0; k < 5; k++) {
                x[2 * k] = centr + hlgth * x2[k];
                x[2 * k + 1] = centr - hlgth * x2[k];
            }
            charon_call(fun, arg, x, y, 10);
            for (int k = 0; k < 5; k++) {
                fval1 = y[2 * k];
                fval2 = y[2 * k + 1];
                fval = fval1 + fval2;
                res21 += w21b[k] * fval;
                resabs += w21b[k] * (fabs(fval1) + fabs(fval2));
                savfun[++ipx] = fval;
                fv3[k] = fval1;
                fv4[k] = fval2;
            }
            *result = res21 * hlgth;
            resabs *= dhlgth;
            reskh = 0.5 * res21;
            resasc = w21b[5] * fabs(fcentr - reskh);
            for (int k = 0; k < 5; k++) {
                resasc += w21a[k] * (fabs(fv1[k] - reskh) + fabs(fv2[k] - reskh)) +
                           w21b[k] * (fabs(fv3[k] - reskh) + fabs(fv4[k] - reskh));
            }
            *abserr = fabs((res21 - res10) * hlgth);
            resasc *= dhlgth;
        } else if (pass == 2) {
            res43 = w43b[11] * fcentr;
            *neval = 43;
            for (int k = 0; k < 10; k++) {
                res43 += savfun[k] * w43a[k];
            }
            for (int k = 0; k < 11; k++) {
                x[2 * k] = centr + hlgth * x3[k];
                x[2 * k + 1] = centr - hlgth * x3[k];
            }
            charon_call(fun, arg, x, y, 22);
            for (int k = 0; k < 11; k++) {
                fval = y[2 * k] + y[2 * k + 1];
                res43 += fval * w43b[k];
                savfun[++ipx] = fval;
            }
            *result = res43 * hlgth;
            *abserr = fabs((res43 - res21) * hlgth);
            resasc = 0.0;
        } else {
            res87 = w87b[22] * fcentr;
            *neval = 87;
            for (int k = 0; k < 21; k++) {
                res87 += savfun[k] * w87a[k];
            }
            for (int k = 0; k < 22; k++) {
                x[2 * k] = centr + hlgth * x4[k];
                x[2 * k + 1] = centr - hlgth * x4[k];
            }
            charon_call(fun, arg, x, y, 44);
            for (int k = 0; k < 22; k++) {
                res87 += w87b[k] * (y[2 * k] + y[2 * k + 1]);
            }
            *result = res87 * hlgth;
            *abserr = fabs((res87 - res43) * hlgth);
            resasc = 0.0;
        }
        if (resasc != 0.0 && *abserr != 0.0) {
            *abserr = resasc * fmin(1.0, pow(200.0 * (*abserr) / resasc, 1.5));
        }
        if (resabs > CHARON_UFLOW / (50.0 * CHARON_EPMACH)) {
            *abserr = fmax((CHARON_EPMACH * 50.0) * resabs, *abserr);
        }
        if (*abserr <= fmax(epsabs, epsrel * fabs(*result))) {
            return 0;
        }
    }
    return ier;
}

// ---------------------------------------------------------------- the two pieces the adaptive driver calls

// dqpsrt: keep the error estimates in descending order and say which subinterval to bisect next.
static void charon_dqpsrt(int limit, int last, int *maxerr, double *errmax, const double *elist, int *iord, int *nrmax)
{
    int ido, isucc, i, jupbn, jbnd, ibeg;
    double errmin;
    if (last <= 2) {
        iord[0] = 1;
        iord[1] = 2;
        return;
    }
    *errmax = elist[*maxerr - 1];
    if (*nrmax != 1) {
        ido = *nrmax - 1;
        for (i = 0; i < ido; i++) {
            isucc = iord[*nrmax - 2 - i];
            if (*errmax <= elist[isucc - 1]) {
                break;
            }
            iord[*nrmax - 1] = isucc;
            *nrmax -= 1;
        }
    }
    jupbn = last;
    if (last > (limit / 2 + 2)) {
        jupbn = limit + 3 - last;
    }
    errmin = elist[last - 1];
    jbnd = jupbn - 1;
    ibeg = *nrmax + 1;
    int inserted = 0;
    if (ibeg <= jbnd) {
        for (i = ibeg - 1; i <= jbnd - 1; i++) {
            isucc = iord[i];
            if (*errmax >= elist[isucc - 1]) {
                iord[i - 1] = *maxerr;
                for (int j = jbnd - 1; j >= i; j--) {
                    iord[j] = iord[j - 1];
                }
                iord[i - 1] = last;
                inserted = 1;
                break;
            }
            iord[i - 1] = isucc;
        }
    }
    if (!inserted) {
        iord[jbnd - 1] = *maxerr;
        iord[jupbn - 1] = last;
    }
    if (errmin < elist[iord[jupbn - 1] - 1]) {
        for (i = jupbn - 2; i >= 0; i--) {
            iord[i] = iord[i + 1];
        }
        iord[0] = last;
    }
    *nrmax = 1;
    for (i = 0; i < last - 1; i++) {
        if (elist[iord[i] - 1] > elist[iord[i + 1] - 1] || i == last - 2) {
            *nrmax = i + 1;
            break;
        }
    }
    if (last == 2) {
        *nrmax = 1;
    }
    *errmax = elist[*maxerr - 1];
    if (*nrmax == 0) {
        *nrmax = 1;
    }
}

// dqelg: Peter Wynn's epsilon algorithm over the table of results, which is the "acceleration by Peter
// Wynn's epsilon algorithm" the header names for QAGS.
static void charon_dqelg(int n, double *epstab, double *result, double *abserr, double *res3la, int *nres)
{
    int limexp = 50, newelm, num, k1, i, k2, k3, ib, ie, indx;
    double e0, e1, e2, e3, res, e1abs, delta2, delta3, err2, err3, tol2, tol3, delta1, err1, tol1, ss, epsinf, error;
    *nres += 1;
    *abserr = CHARON_OFLOW;
    *result = epstab[n - 1];
    if (n < 3) {
        return;
    }
    epstab[n + 1] = epstab[n - 1];
    newelm = (n - 1) / 2;
    epstab[n - 1] = CHARON_OFLOW;
    num = n;
    k1 = n;
    for (i = 0; i < newelm; i++) {
        k2 = k1 - 1;
        k3 = k1 - 2;
        res = epstab[k1 + 1];
        e0 = epstab[k3 - 1];
        e1 = epstab[k2 - 1];
        e2 = res;
        e1abs = fabs(e1);
        delta2 = e2 - e1;
        err2 = fabs(delta2);
        tol2 = fmax(fabs(e2), e1abs) * CHARON_EPMACH;
        delta3 = e1 - e0;
        err3 = fabs(delta3);
        tol3 = fmax(e1abs, fabs(e0)) * CHARON_EPMACH;
        if (err2 > tol2 || err3 > tol3) {
            e3 = epstab[k1 - 1];
            epstab[k1 - 1] = e1;
            delta1 = e1 - e3;
            err1 = fabs(delta1);
            tol1 = fmax(e1abs, fabs(e3)) * CHARON_EPMACH;
            if (!(err1 <= tol1 || err2 <= tol2 || err3 <= tol3)) {
                ss = 1.0 / delta1 + 1.0 / delta2 - 1.0 / delta3;
                epsinf = fabs(ss * e1);
                if (epsinf > 1e-3) {
                    res = e1 + 1.0 / ss;
                    epstab[k1 - 1] = res;
                    k1 -= 2;
                    error = err2 + fabs(res - e2) + err3;
                    if (error > *abserr) {
                        continue;
                    }
                    *abserr = error;
                    *result = res;
                }
            }
        }
        // Convergence within machine accuracy, or an irregular table: result = e2, abserr = err2 + err3.
        else {
            *result = res;
            *abserr = err2 + err3;
            break;
        }
    }
    if (i < newelm) {
        n = 2 * i;
    } else {
        n = 2 * newelm;
        if (n == limexp) {
            n = 2 * (limexp / 2) - 1;
        }
        ib = 1;
        if ((num / 2) * 2 == num) {
            ib = 2;
        }
        ie = newelm + 1;
        for (i = 0; i < ie; i++) {
            epstab[ib - 1] = epstab[ib + 1];
            ib += 2;
        }
        if (num != n) {
            indx = num - n + 1;
            for (i = 0; i < n; i++) {
                epstab[i] = epstab[indx - 1];
                indx += 1;
            }
        }
        if (*nres < 4) {
            res3la[*nres - 1] = *result;
            *abserr = CHARON_OFLOW;
            goto done;
        }
    }
    *abserr = fabs(*result - res3la[2]) + fabs(*result - res3la[1]) + fabs(*result - res3la[0]);
    res3la[0] = res3la[1];
    res3la[1] = res3la[2];
    res3la[2] = *result;
done:
    *abserr = fmax(*abserr, 5.0 * CHARON_EPMACH * fabs(*result));
}

// ---------------------------------------------------------------- the adaptive driver

// dqk15i: the 15-point rule over an interval with a bound at infinity, mapped onto (0,1). QUADPACK reaches it
// through dqagie only; QAGS with an infinite bound is this.
static void charon_dqk15i(CharonIntegrand fun, void *arg, double boun, int inf, double a, double b, double *result,
                          double *abserr, double *resabs, double *defabs)
{
    double hlgth = 0.5 * (b - a);
    double centr = 0.5 * (b + a);
    // dinf is 1 for a finite side of the interval and 0 for an infinite one, so the transformation below is
    // the identity where the caller's bound is finite and x = boun + (1 - t) / t where it is not.
    double dinf = inf == 1 ? 0.0 : 1.0;
    double fv1[8], fv2[8];
    double resg = 0.0, resk, resabs_value, resasc, fc, reskh, fsum, absc, absc1, absc2;
    double fval1, fval2, tabsc1;
    double xs[14], ys[14], mirrored;
    const int centre = 7;
    const int pairs = 7;
    tabsc1 = boun + dinf * (1.0 - centr) / centr;
    xs[0] = tabsc1;
    charon_call(fun, arg, xs, ys, 1);
    fval1 = ys[0];
    if (inf == 2) {
        xs[0] = -tabsc1;
        charon_call(fun, arg, xs, ys, 1);
        fval1 += ys[0];
    }
    fc = (fval1 / centr) / centr;
    for (int j = 0; j < pairs; j++) {
        absc = hlgth * k15_xgk[j];
        absc1 = centr - absc;
        absc2 = centr + absc;
        xs[2 * j] = boun + dinf * (1.0 - absc1) / absc1;
        xs[2 * j + 1] = boun + dinf * (1.0 - absc2) / absc2;
    }
    charon_call(fun, arg, xs, ys, 2 * pairs);
    resk = k15_wgk[centre] * fc;
    resabs_value = fabs(resk);
    resg = k15_wg[7] * fc;
    for (int j = 0; j < 3; j++) {
        absc1 = centr - hlgth * k15_xgk[j];
        absc2 = centr + hlgth * k15_xgk[j];
        fval1 = ys[2 * j];
        fval2 = ys[2 * j + 1];
        if (inf == 2) {
            mirrored = boun + dinf * (1.0 - absc1) / absc1;
            xs[0] = -mirrored;
            charon_call(fun, arg, xs, ys, 1);
            fval1 += ys[0];
            mirrored = boun + dinf * (1.0 - absc2) / absc2;
            xs[0] = -mirrored;
            charon_call(fun, arg, xs, ys, 1);
            fval2 += ys[0];
        }
        fval1 = (fval1 / absc1) / absc1;
        fval2 = (fval2 / absc2) / absc2;
        fv1[j] = fval1;
        fv2[j] = fval2;
        fsum = fval1 + fval2;
        resg += k15_wg[j] * fsum;
        resk += k15_wgk[2 * j + 1] * fsum;
        resabs_value += k15_wgk[2 * j + 1] * (fabs(fval1) + fabs(fval2));
    }
    // The four points the 7-point Gauss rule does not take: the odd-indexed ones below the centre.
    for (int i = 2; i < pairs; i += 2) {
        absc = hlgth * k15_xgk[i];
        absc1 = centr - absc;
        absc2 = centr + absc;
        fval1 = ys[2 * i];
        fval2 = ys[2 * i + 1];
        if (inf == 2) {
            mirrored = boun + dinf * (1.0 - absc1) / absc1;
            xs[0] = -mirrored;
            charon_call(fun, arg, xs, ys, 1);
            fval1 += ys[0];
            mirrored = boun + dinf * (1.0 - absc2) / absc2;
            xs[0] = -mirrored;
            charon_call(fun, arg, xs, ys, 1);
            fval2 += ys[0];
        }
        fval1 = (fval1 / absc1) / absc1;
        fval2 = (fval2 / absc2) / absc2;
        resk += k15_wgk[2 * i + 1] * (fval1 + fval2);
        resabs_value += k15_wgk[2 * i + 1] * (fabs(fval1) + fabs(fval2));
    }
    reskh = resk * 0.5;
    resasc = k15_wgk[centre] * fabs(fc - reskh);
    for (int j = 0; j < 3; j++) {
        resasc += k15_wgk[2 * j + 1] * (fabs(fv1[j] - reskh) + fabs(fv2[j] - reskh));
    }
    *result = resk * hlgth;
    resasc *= hlgth;
    resabs_value *= hlgth;
    *abserr = fabs((resk - resg) * hlgth);
    if (resasc != 0.0 && *abserr != 0.0) {
        *abserr = resasc * fmin(1.0, pow(200.0 * (*abserr) / resasc, 1.5));
    }
    if (resabs_value > CHARON_UFLOW / (50.0 * CHARON_EPMACH)) {
        *abserr = fmax((CHARON_EPMACH * 50.0) * resabs_value, *abserr);
    }
    if (resabs) {
        *resabs = resabs_value;
    }
    if (defabs) {
        *defabs = resabs_value;
    }
}

// dqagse and dqagie are one driver: the same subdivision, the same error bookkeeping and the same epsilon
// extrapolation, over either the caller's interval with the chosen rule or (0,1) with dqk15i. `inf` is
// 0 for the finite case and 1 or 2 for a bound at infinity, as dqagie names it.
static int charon_dqags(CharonIntegrand fun, void *arg, double a, double b, double epsabs, double epsrel,
                        size_t limit, const CharonRule *rule, int inf, double *result, double *abserr, int *neval,
                        double *work, int *iwork)
{
    double alist[2 * 1000], blist[2 * 1000], rlist[2 * 1000], elist[2 * 1000];
    double rlist2[53], res3la[3], epstab[52];
    int iord[2 * 1000];
    int last, k, ier = 0, ierro = 0, maxerr, nrmax, nres, ktmin, numrl2, iroff1, iroff2, iroff3, ksgn;
    int extrap, noext, id, jupbnd;
    double uflow = CHARON_UFLOW, oflow = CHARON_OFLOW;
    double dres, errbnd, defabs, resabs, errmax, area, errsum, area1, error1, defab1, area2, error2, defab2;
    double area12, erro12, erlast, small, erlarg, ertest, correc, reseps, abseps, a1, b1, a2, b2;
    (void)k;
    (void)iwork;
    (void)work;
    *neval = 0;
    last = 0;
    *result = 0.0;
    *abserr = 0.0;
    if (inf == 0) {
        alist[0] = a;
        blist[0] = b;
    } else {
        alist[0] = 0.0;
        blist[0] = 1.0;
    }
    rlist[0] = 0.0;
    elist[0] = 0.0;
    if (epsabs <= 0.0 && epsrel < fmax(50.0 * CHARON_EPMACH, 0.5e-28)) {
        return 6;
    }
    if (inf == 0) {
        charon_dqk(rule, fun, arg, a, b, result, abserr, &resabs, &defabs);
    } else {
        double boun = inf == 2 ? 0.0 : a;
        if (inf == 2) {
            boun = 0.0;
        } else {
            boun = a;
        }
        charon_dqk15i(fun, arg, boun, inf, 0.0, 1.0, result, abserr, &resabs, &defabs);
    }
    dres = fabs(*result);
    errbnd = fmax(epsabs, epsrel * dres);
    last = 1;
    rlist[0] = *result;
    elist[0] = *abserr;
    iord[0] = 1;
    if (*abserr <= 100.0 * CHARON_EPMACH * defabs && *abserr > errbnd) {
        ier = 2;
    }
    if (limit == 1) {
        ier = 1;
    }
    if (ier != 0 || !(*abserr <= errbnd && *abserr != resabs) || *abserr == 0.0) {
        goto finish;
    }
    rlist2[0] = *result;
    errmax = *abserr;
    maxerr = 1;
    area = *result;
    errsum = *abserr;
    *abserr = oflow;
    nrmax = 1;
    nres = 0;
    numrl2 = 2;
    ktmin = 0;
    extrap = 0;
    noext = 0;
    iroff1 = iroff2 = iroff3 = 0;
    ksgn = -1;
    if (dres >= (1.0 - 50.0 * CHARON_EPMACH) * defabs) {
        ksgn = 1;
    }
    for (last = 2; last <= (int)limit; last++) {
        a1 = alist[maxerr - 1];
        b1 = 0.5 * (alist[maxerr - 1] + blist[maxerr - 1]);
        a2 = b1;
        b2 = blist[maxerr - 1];
        erlast = errmax;
        if (inf == 0) {
            charon_dqk(rule, fun, arg, a1, b1, &area1, &error1, &resabs, &defab1);
            charon_dqk(rule, fun, arg, a2, b2, &area2, &error2, &resabs, &defab2);
        } else {
            charon_dqk15i(fun, arg, a1, inf, a1, b1, &area1, &error1, &resabs, &defab1);
            charon_dqk15i(fun, arg, a2, inf, a2, b2, &area2, &error2, &resabs, &defab2);
        }
        area12 = area1 + area2;
        erro12 = error1 + error2;
        errsum += erro12 - errmax;
        area += area12 - rlist[maxerr - 1];
        if (defab1 != error1 && defab2 != error2) {
            if (!(fabs(rlist[maxerr - 1] - area12) > 1e-5 * fabs(area12) || erro12 < 0.99 * errmax)) {
                if (extrap) {
                    iroff2 += 1;
                } else {
                    iroff1 += 1;
                }
            }
            if (last > 10 && erro12 > errmax) {
                iroff3 += 1;
            }
        }
        rlist[maxerr - 1] = area1;
        rlist[last - 1] = area2;
        errbnd = fmax(epsabs, epsrel * fabs(area));
        if (iroff1 + iroff2 >= 10 || iroff3 >= 20) {
            ier = 2;
        }
        if (iroff2 >= 5) {
            ierro = 3;
        }
        if ((size_t)last == limit) {
            ier = 1;
        }
        if (fmax(fabs(a1), fabs(b2)) <= (1.0 + 1000.0 * CHARON_EPMACH) * (fabs(a2) + 10000.0 * uflow)) {
            ier = 4;
        }
        if (error2 <= error1) {
            alist[last - 1] = a2;
            blist[maxerr - 1] = b1;
            blist[last - 1] = b2;
            elist[maxerr - 1] = error1;
            elist[last - 1] = error2;
        } else {
            alist[maxerr - 1] = a2;
            alist[last - 1] = a1;
            blist[last - 1] = b1;
            rlist[maxerr - 1] = area2;
            rlist[last - 1] = area1;
            elist[maxerr - 1] = error2;
            elist[last - 1] = error1;
        }
        charon_dqpsrt((int)limit, last, &maxerr, &errmax, elist, iord, &nrmax);
        if (errsum <= errbnd) {
            goto sum_up;
        }
        if (ier != 0) {
            goto finish;
        }
        if (last == 2) {
            small = fabs(b - a) * 0.375;
            erlarg = errsum;
            ertest = errbnd;
            rlist2[1] = area;
            continue;
        }
        if (noext) {
            continue;
        }
        erlarg -= erlast;
        if (fabs(b1 - a1) > small) {
            erlarg += erro12;
        }
        if (extrap) {
            goto extrapolate;
        }
        if (fabs(blist[maxerr - 1] - alist[maxerr - 1]) > small) {
            continue;
        }
        extrap = 1;
        nrmax = 2;
extrapolate:
        if (ierro == 3 || erlarg <= ertest) {
            goto do_extrapolate;
        }
        id = nrmax;
        jupbnd = last;
        if (last > (2 + (int)limit / 2)) {
            jupbnd = (int)limit + 3 - last;
        }
        for (k = id; k <= jupbnd; k++) {
            maxerr = iord[nrmax - 1];
            errmax = elist[maxerr - 1];
            if (fabs(blist[maxerr - 1] - alist[maxerr - 1]) > small) {
                goto next_interval;
            }
            nrmax += 1;
        }
do_extrapolate:
        numrl2 += 1;
        rlist2[numrl2 - 1] = area;
        charon_dqelg(numrl2, epstab, &reseps, &abseps, res3la, &nres);
        ktmin += 1;
        if (ktmin > 5 && *abserr < 0.01 * errsum) {
            ier = 5;
        }
        if (abseps < *abserr) {
            ktmin = 0;
            *abserr = abseps;
            *result = reseps;
            correc = erlarg;
            ertest = fmax(epsabs, epsrel * fabs(reseps));
            if (*abserr <= ertest) {
                goto finish;
            }
        }
        if (numrl2 == 1) {
            noext = 1;
        }
        if (ier == 5) {
            goto finish;
        }
        maxerr = iord[0];
        errmax = elist[maxerr - 1];
        nrmax = 1;
        extrap = 0;
        small *= 0.5;
        erlarg = errsum;
    next_interval:;
    }
sum_up:
    if (*abserr != oflow) {
        goto finish;
    }
    *result = 0.0;
    for (k = 0; k < last; k++) {
        *result += rlist[k];
    }
    *abserr = errsum;
finish:
    if (ier + ierro == 0) {
        goto divergence;
    }
    if (ierro == 3) {
        *abserr += correc;
    }
    if (ier == 0) {
        ier = 3;
    }
    if (*result != 0.0 && area != 0.0) {
        if (!(*abserr / fabs(*result) > errsum / fabs(area))) {
            goto done;
        }
        goto sum_up;
    }
    if (*abserr > errsum) {
        goto sum_up;
    }
    if (area == 0.0) {
        goto done;
    }
divergence:
    if (ksgn == -1 && fmax(fabs(*result), fabs(area)) <= defabs * 0.01) {
        goto done;
    }
    if (0.01 > (*result / area) || (*result / area) > 1000.0 || errsum > fabs(area)) {
        ier = 6;
    }
done:
    if (ier > 2) {
        ier -= 1;
    }
    *neval = 42 * last - 21;
    return ier;
}

// ---------------------------------------------------------------- quadrature_integrate

// QUADPACK's ier as the header's codes. Measured at 1e-300 tolerances: QNG and QAGS answer -101 and QAG -102,
// so 1 and 5 are the accuracy codes and 2, 3 and 4 the behaviour ones.
static quadrature_status charon_status_of(int ier)
{
    switch (ier) {
        case 0:
            return QUADRATURE_SUCCESS;
        case 6:
            return QUADRATURE_INVALID_ARG_ERROR;
        case 1:
        case 5:
            return QUADRATURE_INTEGRATE_MAX_EVAL_ERROR;
        default:
            return QUADRATURE_INTEGRATE_BAD_BEHAVIOUR_ERROR;
    }
}

double quadrature_integrate(const quadrature_integrate_function *__f, double __a, double __b,
                           const quadrature_integrate_options *__options, quadrature_status *__status,
                           double *__abs_error, size_t __workspace_size, void *__restrict __workspace)
{
    if (__status) {
        *__status = QUADRATURE_INVALID_ARG_ERROR;
    }
    if (!__f || !__options) {
        return 0.0;
    }
    const CharonIntegrand fun = __f->fun;
    void *arg = __f->fun_arg;
    if (!fun) {
        return 0.0;
    }
    const size_t per_interval = __options->integrator == QUADRATURE_INTEGRATE_QAGS
                                    ? QUADRATURE_INTEGRATE_QAGS_WORKSPACE_PER_INTERVAL
                                    : QUADRATURE_INTEGRATE_QAG_WORKSPACE_PER_INTERVAL;
    // The rule the caller named, and whether it named one at all: 0 and 21 are the 21-point rule, and a count
    // the header does not list is the refusal (measured: 10, 20 and 100 answer 0 with status -2, and 15, 31,
    // 41, 51 and 61 each make the callback see its own count).
    const CharonRule *rule = NULL;
    switch (__options->integrator) {
        case QUADRATURE_INTEGRATE_QNG:
            break;
        case QUADRATURE_INTEGRATE_QAG:
        case QUADRATURE_INTEGRATE_QAGS:
            switch (__options->qag_points_per_interval) {
                case 0:
                case 21:
                    rule = &charon_k21;
                    break;
                case 15:
                    rule = &charon_k15;
                    break;
                case 31:
                    rule = &charon_k31;
                    break;
                case 41:
                    rule = &charon_k41;
                    break;
                case 51:
                    rule = &charon_k51;
                    break;
                case 61:
                    rule = &charon_k61;
                    break;
                default:
                    if (__abs_error) {
                        *__abs_error = 0.0;
                    }
                    return 0.0;
            }
            break;
        default:
            // An integrator the enumeration does not name leaves abs_error as the caller left it (measured:
            // 3 and -1 both answer 0 with QUADRATURE_ERROR and the caller's -1 is still there).
            if (__status) {
                *__status = QUADRATURE_ERROR;
            }
            return 0.0;
    }
    // An infinite bound is QAGS's alone (measured: QNG over one answers QUADRATURE_INVALID_ARG_ERROR).
    int inf = 0;
    double a = __a;
    double b = __b;
    if (__a != __a || __b != __b) {
        return 0.0;
    }
    if (isinf(__a) || isinf(__b)) {
        if (__options->integrator != QUADRATURE_INTEGRATE_QAGS) {
            return 0.0;
        }
        // QUADPACK's QAGI: -inf and +inf on the same side is 1, and a bound at each end is 2.
        if (isinf(__a) && isinf(__b)) {
            inf = 2;
            a = 0.0;
            b = 0.0;
        } else {
            inf = 1;
            a = isinf(__a) ? (isinf(__b) && __b < 0 ? __b : __b) : __a;
            if (isinf(__a)) {
                a = __b;
            }
            if (isinf(__b)) {
                a = __a;
            }
        }
    }
    double result = 0.0;
    double abserr = 0.0;
    int neval = 0;
    int ier;
    if (__options->integrator == QUADRATURE_INTEGRATE_QNG) {
        // QNG needs no workspace and ignores max_intervals (measured: 0, 1, 2, 10, 100 and 1000 all answer
        // the same, and 43 evaluations).
        ier = charon_dqng(fun, arg, a, b, __options->abs_tolerance, __options->rel_tolerance, &result, &abserr, &neval);
    } else {
        // The limit is max_intervals, unless a workspace was given, in which case it is what the workspace
        // holds (measured: a QAG workspace of 32 bytes gives one interval and answers -101, 100 bytes gives
        // three and succeeds, and 31 bytes answers -2; QAGS needs 152 for one).
        size_t limit = __options->max_intervals;
        if (__workspace) {
            limit = __workspace_size / per_interval;
        }
        if (limit < 1) {
            if (__abs_error) {
                *__abs_error = 0.0;
            }
            return 0.0;
        }
        if (limit > 1000) {
            limit = 1000;
        }
        ier = charon_dqags(fun, arg, a, b, __options->abs_tolerance, __options->rel_tolerance, limit, rule, inf,
                           &result, &abserr, &neval, (double *)__workspace, NULL);
    }
    if (__status) {
        *__status = charon_status_of(ier);
    }
    if (__abs_error) {
        *__abs_error = abserr;
    }
    return result;
}
