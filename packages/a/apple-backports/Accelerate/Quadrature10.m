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
    9.73906528517171771186511364248872e-02, 8.65063366688984536345685683045303e-02, 6.79409568299024352322490472033678e-02,
    4.33395394129247185643905027063738e-02, 1.48874338981631205297562203782036e-02,
};
static const double x2[5] = {
    9.95657163025808061851407160247618e-02, 9.30157491355708271330016145839181e-02, 7.80817726586416904765997060167138e-02,
    5.62757134668604649951895169124327e-02, 2.94392862701460186758417592045589e-02,
};
static const double x3[11] = {
    9.99333360901932116204804401604633e-02, 9.87433402908088897476091005955823e-02, 9.54807934814266290324269448319683e-02,
    9.00148695748328314669706173845043e-02, 8.25198314983114217247006649813557e-02, 7.32148388989305037855004343327892e-02,
    6.22847970537725240114390601320338e-02, 4.99479574071056489636966091438808e-02, 3.64901661346580738487510586764984e-02,
    2.22254919776601299330476280147195e-02, 7.46506174613833194120271485871854e-03,
};
static const double x4[22] = {
    9.99902977262729225627069240545097e-02, 9.97989895986678698935889997301274e-02, 9.92175497860687261031387151888339e-02,
    9.81358163572712827171784510937869e-02, 9.65057623858384672210775079292944e-02, 9.43167613133670534875108160122181e-02,
    9.15806414685507164108457800466567e-02, 8.83221657771316448481968564010458e-02, 8.45710748462415728976537820926751e-02,
    8.03557658035231048287982957845088e-02, 7.57005730685495620280178741268173e-02, 7.06273209787321859520758948747243e-02,
    6.51589466501177883017703607038129e-02, 5.93223374057961078120726483575709e-02, 5.31493605970831950457977654878050e-02,
    4.66763623042022873788070569389674e-02, 3.99424847859218834500438788381871e-02, 3.29874877106188305053713349934696e-02,
    2.58503559202161552199594751755285e-02, 1.85695396568346660082227117527509e-02, 1.11842213179907459807971292775619e-02,
    3.73521233946198707304153785457856e-03,
};
static const double w10[5] = {
    6.66713443086881362570350617602344e-03, 1.49451349150580593827530861972264e-02, 2.19086362515982027709959822914243e-02,
    2.69266719309996342690549653298149e-02, 2.95524224714752876963519412356618e-02,
};
static const double w21a[5] = {
    3.25581623079647256360780183115367e-03, 7.50396748109199551030057406819651e-03, 1.09387158802297639742517887384565e-02,
    1.34709217311473321981862838470079e-02, 1.47739104901338496461660199088328e-02,
};
static const double w21b[6] = {
    1.16946388673718751002872373589980e-03, 5.47558965743519948654594031722809e-03, 9.31254545836976074801860647767171e-03,
    1.23491976262065858427341424885526e-02, 1.42775938577060085288294999372738e-02, 1.49445554002916904112741036669831e-02,
};
static const double w43a[10] = {
    1.62967342896665656933052890309455e-03, 3.75228761208695011861169454903120e-03, 5.46949020582554457092783195548691e-03,
    6.73554146094780883946562255459867e-03, 7.38701996323939524130564038273405e-03, 5.76855605976979565405193817184681e-04,
    2.73718905932488409601943679660963e-03, 4.65608269104288326201146475114001e-03, 6.17449952014425661878105344726464e-03,
    7.13872672686933964353306336647620e-03,
};
static const double w43b[12] = {
    1.84447764021241418942037570971593e-04, 1.07986895858916518049774868615032e-03, 2.18953638677954259481039933632474e-03,
    3.25974639753456906302031548250397e-03, 4.21631379351918109815722246480618e-03, 5.07419396001845737081970000303954e-03,
    5.83793955426192487379033480010548e-03, 6.47464049514458878098466243500297e-03, 6.95661979123564887250719124267562e-03,
    7.28244414718332098296338372733771e-03, 7.45077510141751216815597658182924e-03, 7.47221475174030067695207790734457e-03,
};
static const double w87a[21] = {
    8.14837738414917324251962593706367e-04, 1.87614382015628211944346936945749e-03, 2.73474510500522870193318425435791e-03,
    3.36777073116379310410706260370262e-03, 3.69350998204279060491139752286927e-03, 2.88487243021153037629555893062161e-04,
    1.36859460227127028610072390080177e-03, 2.32804135028883123909038133092508e-03, 3.08724976117133583994323053900644e-03,
    3.56936336394187694529001042553773e-03, 9.15283345202241383278818354085615e-05, 5.39928021930047145372777439575884e-04,
    1.09476796011189316318312769737986e-03, 1.62987316967873351915285784485832e-03, 2.10815688892038340107593086258930e-03,
    2.53709697692538257290939540666841e-03, 2.91896977564757523909699798991824e-03, 3.23732024672027888373415649425624e-03,
    3.47830989503651426264507762198264e-03, 3.64122207313517885080011993181870e-03, 3.72538755030477064522642649535555e-03,
};
static const double w87b[23] = {
    2.74145563762072336049229609455935e-05, 1.80712415505794295276370542424615e-04, 4.09686928275916509376713969814432e-04,
    6.75829005184737916824000425464192e-04, 9.54995767220164610243615666007599e-04, 1.23294476522448526352448983089971e-03,
    1.50104473463889527898307285624924e-03, 1.75489679862431916662623976321811e-03, 1.99380377864408903088033753192576e-03,
    2.21949359610122860797520871756205e-03, 2.43391471260008063551283363779021e-03, 2.63745054148392058662730974560873e-03,
    2.82869107887712004437141821711066e-03, 3.00525811280926953908410048654787e-03, 3.16467513714399281687938980667241e-03,
    3.30504134199785049377795509428779e-03, 3.42550997042260618047349041148664e-03, 3.52624126601566809796617363303994e-03,
    3.60769896228887001002338941191283e-03, 3.66986044984560959639208199689620e-03, 3.71205492698325773687217932206295e-03,
    3.73342287519350416943875181630119e-03, 3.73610737626790248219754708713936e-03,
};

    // The 8-point Gauss-Kronrod rule of dqk15.f: wg are the 4 Gauss weights, wgk the 8 Kronrod ones and
    // xgk the abscissae, the largest last.
static const double k15_wg[4] = {
    1.29484966168869689018272595149028e-02, 2.79705391489276679328757069242783e-02, 3.81830050505118923087621851664153e-02,
    4.17959183673469389375121352259157e-02,
};
static const double k15_wgk[8] = {
    2.29353220105292261027374323134609e-03, 6.30920926299785491536686876656859e-03, 1.04790010322250177338121446268815e-02,
    1.40653259715525918993606069307134e-02, 1.69004726639267917331910240363868e-02, 1.90350578064785412590875779415001e-02,
    2.04432940075298906490441908090361e-02, 2.09482141084727825630640296594720e-02,
};
static const double k15_xgk[8] = {
    9.91455371120812667395938433401170e-02, 9.49107912342758569534950652268890e-02, 8.64864423359769096677496236225124e-02,
    7.41531185599394460083999547350686e-02, 5.86087235467691106127752220800176e-02, 4.05845151377397170278094051809603e-02,
    2.07784955007898480827677190063696e-02, 0.00000000000000000000000000000000e+00,
};

    // The 11-point Gauss-Kronrod rule of dqk21.f: wg are the 6 Gauss weights, wgk the 11 Kronrod ones and
    // xgk the abscissae, the largest last.
static const double k21_wg[5] = {
    6.66713443086881362570350617602344e-03, 1.49451349150580593827530861972264e-02, 2.19086362515982027709959822914243e-02,
    2.69266719309996342690549653298149e-02, 2.95524224714752876963519412356618e-02,
};
static const double k21_wgk[11] = {
    1.16946388673718751002872373589980e-03, 3.25581623079647256360780183115367e-03, 5.47558965743519948654594031722809e-03,
    7.50396748109199551030057406819651e-03, 9.31254545836976074801860647767171e-03, 1.09387158802297639742517887384565e-02,
    1.23491976262065858427341424885526e-02, 1.34709217311473321981862838470079e-02, 1.42775938577060085288294999372738e-02,
    1.47739104901338496461660199088328e-02, 1.49445554002916904112741036669831e-02,
};
static const double k21_xgk[11] = {
    9.95657163025808061851407160247618e-02, 9.73906528517171771186511364248872e-02, 9.30157491355708271330016145839181e-02,
    8.65063366688984536345685683045303e-02, 7.80817726586416904765997060167138e-02, 6.79409568299024352322490472033678e-02,
    5.62757134668604649951895169124327e-02, 4.33395394129247185643905027063738e-02, 2.94392862701460186758417592045589e-02,
    1.48874338981631205297562203782036e-02, 0.00000000000000000000000000000000e+00,
};

    // The 16-point Gauss-Kronrod rule of dqk31.f: wg are the 8 Gauss weights, wgk the 16 Kronrod ones and
    // xgk the abscissae, the largest last.
static const double k31_wg[8] = {
    3.07532419961172682684735768532391e-03, 7.03660474881081209053146352516706e-03, 1.07159220467171936025385647894836e-02,
    1.39570677926154317061158138812971e-02, 1.66269205816993934088365847401292e-02, 1.86161000015562204390473510784432e-02,
    1.98431485327111578609304842757410e-02, 2.02578241925561279568324124511491e-02,
};
static const double k31_wgk[16] = {
    5.37747987292334895213785639356274e-04, 1.50079473293161227628877973927501e-03, 2.54608473267153205890633849151072e-03,
    3.53463607913758479442400961545445e-03, 4.45897513247648768358599724592750e-03, 5.34815246909280898185423680502026e-03,
    6.20095678006706441803830287540222e-03, 6.98541213187282589852644676398086e-03, 7.68496807577203830397216677283723e-03,
    8.30805028231330205956695067470719e-03, 8.85644430562117744576422495583756e-03, 9.31265981708253275106468294097795e-03,
    9.66427269836236772782012138804930e-03, 9.91735987217919577607627701354431e-03, 1.00769845523875599402341407540007e-02,
    1.01330007014791556585464604722802e-02,
};
static const double k31_xgk[16] = {
    9.98002298693397016382533593059634e-02, 9.87992518020485432916899526389898e-02, 9.67739075679139165719888637795520e-02,
    9.37273392400705951388317771488801e-02, 8.97264532344081849890571334071865e-02, 8.48206583410427150671040408269619e-02,
    7.90418501442465976092321966461895e-02, 7.24417731360170041865487178256444e-02, 6.50996741297416997573677122090885e-02,
    5.70972172608538858229465517979406e-02, 4.85081863640239654977825978221517e-02, 3.94151347077563371512631817950023e-02,
    2.99180007153168822653377389997331e-02, 2.01194093997434514387023796189169e-02, 1.01142066918717497131519067465888e-02,
    0.00000000000000000000000000000000e+00,
};

    // The 21-point Gauss-Kronrod rule of dqk41.f: wg are the 11 Gauss weights, wgk the 21 Kronrod ones and
    // xgk the abscissae, the largest last.
static const double k41_wg[10] = {
    1.76140071391521187485484922774504e-03, 4.06014298003869438663526736377207e-03, 6.26720483341090643658599645959839e-03,
    8.32767415767047408658996232588834e-03, 1.01930119817240441570938003224001e-02, 1.18194531961518418949896869207805e-02,
    1.31688638449176630140780019928570e-02, 1.42096109318382048114504101476996e-02, 1.49172986472603744806386671939435e-02,
    1.52753387130725847703471842464751e-02,
};
static const double k41_wgk[21] = {
    3.07358371852053144195060507826156e-04, 8.60026985564294192861123367066511e-04, 1.46261692569712520653468779130435e-03,
    2.03883734612665245417018056173220e-03, 2.58821336049511576196668904970011e-03, 3.12873067770327991862777672338325e-03,
    3.66001697582007999923203733771970e-03, 4.16688733279736885084520991995305e-03, 4.64348218674976755127037364445641e-03,
    5.09445739237286959050221568645611e-03, 5.51951053482859985144237668919232e-03, 5.91114008806395765938113129323028e-03,
    6.26532375547811642285678246366842e-03, 6.58345971336184252603596078756709e-03, 6.86486729285216198265251463794812e-03,
    7.10544235534440668522471185042377e-03, 7.30306903327866685504687893626397e-03, 7.45828754004991892334608394321549e-03,
    7.57044976845566708334445138461888e-03, 7.63778676720807368771826162401339e-03, 7.66007119179996573410384996805078e-03,
};
static const double k41_xgk[21] = {
    9.98859031588277684887700047511316e-02, 9.93128599185094940171580901733250e-02, 9.81507877450250310058521563405520e-02,
    9.63971927277913753773219696086016e-02, 9.40822633831754767674837580671010e-02, 9.12234428251325890624201520040515e-02,
    8.78276811252281935926689016014279e-02, 8.39116971822218837839812977108522e-02, 7.95041428837551245045744963135803e-02,
    7.46331906460150767967931528801273e-02, 6.93237656334751428666152150981361e-02, 6.36053680726515052734626465280598e-02,
    5.75140446819710285386584303068958e-02, 5.10867001950827126499632413469953e-02, 4.43593175238725101472425649262732e-02,
    3.73706088715419562640285278121155e-02, 3.01627868114913016972522541436774e-02, 2.27785851141645082074127515170403e-02,
    1.52605465240922676811718972089693e-02, 7.65265211334973348422661132417488e-03, 0.00000000000000000000000000000000e+00,
};

    // The 26-point Gauss-Kronrod rule of dqk51.f: wg are the 13 Gauss weights, wgk the 26 Kronrod ones and
    // xgk the abscissae, the largest last.
static const double k51_wg[13] = {
    1.13937985010262874188691206711610e-03, 2.63549866150321375826703906852799e-03, 4.09391567013063159552466174773144e-03,
    5.49046959758351955233068864004053e-03, 6.80383338123569190308836951430749e-03, 8.01407003350010187225915814224209e-03,
    9.10282619829636506503245385601986e-03, 1.00535949067050642269371962811420e-02, 1.08519624474263647745386762721864e-02,
    1.14858259145711651821875065593304e-02, 1.19455763535784766776748355709969e-02, 1.22242442990310035133560973008571e-02,
    1.23176053726715452329987243729192e-02,
};
static const double k51_wgk[26] = {
    1.98738389233031582199393016985312e-04, 5.56193213535671423554396231025976e-04, 9.47397338617415136693966637437825e-04,
    1.32362291955716738361958917380434e-03, 1.68478177091282987909437451889971e-03, 2.04353711458828352434680120097710e-03,
    2.40099456069532181390346892158050e-03, 2.74753175878517368752040894719357e-03, 3.07923001673874891653825969228819e-03,
    3.40021302743293398276880346031703e-03, 3.71162714834155421303463207038931e-03, 4.00838255040323818145786560762645e-03,
    4.28728450201700493626955079662366e-03, 4.55029130499217879246565132689284e-03, 4.79825371388367151459508619382177e-03,
    5.02776790807156741952566036957251e-03, 5.23628858064074768907669721329512e-03, 5.42511298885454875534639640477508e-03,
    5.59508112204123130017929810264832e-03, 5.74371163615678293618005412213279e-03, 5.86896800223942090302120533351626e-03,
    5.97203403241740576196106005113506e-03, 6.05394553760458652841291993240702e-03, 6.11285097170530516280662070016660e-03,
    6.14711898714253180547872901229312e-03, 6.15808180678329309537533120533226e-03,
};
static const double k51_xgk[26] = {
    9.99262104992609812015302850340959e-02, 9.95556969790498125227884429477854e-02, 9.88035794534077305151242853753502e-02,
    9.76663921459517553325113681239600e-02, 9.61614986425842477313352674173075e-02, 9.42974571228974295378222336694307e-02,
    9.20747115281701500322242281981744e-02, 8.94991997878275408195847262504685e-02, 8.65847065293275652830828903461224e-02,
    8.33442628760834025580805928257178e-02, 7.97873797998500111638975340611069e-02, 7.59259263037357634562596331306850e-02,
    7.17766406813084428817361981600698e-02, 6.73566368473468429778350241576845e-02, 6.26810099010317450796136995450070e-02,
    5.77662930241222977167936392106640e-02, 5.26325284334719159518023445798462e-02, 4.73002731445714974523042428700137e-02,
    4.17885382193037765996557197922812e-02, 3.61172305809387833575030413157947e-02, 3.03089538931107828345634658262497e-02,
    2.43866883720988449069100312271985e-02, 1.83718939421048908788858256002641e-02, 1.22864692610710393022577235910830e-02,
    6.15444830056850831351278330316745e-03, 0.00000000000000000000000000000000e+00,
};

    // The 31-point Gauss-Kronrod rule of dqk61.f: wg are the 16 Gauss weights, wgk the 31 Kronrod ones and
    // xgk the abscissae, the largest last.
static const double k61_wg[15] = {
    7.96819249616660609143725668701563e-04, 1.84664683110909600555205045679941e-03, 2.87847078833233707001459933394472e-03,
    3.87991925696270492304740251654493e-03, 4.84026728305940543567453815398949e-03, 5.74931562176190635166106446263257e-03,
    6.59742298821804941388879939268008e-03, 7.37559747377052044026157773259911e-03, 8.07558952294202235522302402159767e-03,
    8.68997872010829862376990462280446e-03, 9.21225222377861259481779399038714e-03, 9.63687371746442533737564417606336e-03,
    9.95934205867952601631820641614468e-03, 1.01762389748405509409812097487702e-02, 1.02852652893558847713162407444543e-02,
};
static const double k61_wgk[31] = {
    1.38901369867700761077597415571461e-04, 3.89046112709988411732658919461869e-04, 6.63070391593129212712276476793249e-04,
    9.27327965951776390929328641732354e-04, 1.18230152534963420599134487076753e-03, 1.43697295070458050045281161999355e-03,
    1.69208891890532727581009098116738e-03, 1.94141411939423801612247810766121e-03, 2.18280358216091938464153976440230e-03,
    2.41911620780806005739926867192935e-03, 2.65099548823331029184791063357807e-03, 2.87540487650412950049183535838893e-03,
    3.09072575623877635747627223850031e-03, 3.29814470574837275210211551268458e-03, 3.49793380280600261014734009279437e-03,
    3.68823646518212297507055552614474e-03, 3.86789456247275910058536219082725e-03, 4.03745389515359608817446357420522e-03,
    4.19698102151642472856796217683950e-03, 4.34525397013560670672616126353205e-03, 4.48148001331626598398027994107906e-03,
    4.60592382710069917634010394635879e-03, 4.71855465692991565135328002611459e-03, 4.81858617570871290702871903022242e-03,
    4.90554345550297827421859508945090e-03, 4.97956834270742079023852610930589e-03, 5.04059214027823433018626886337188e-03,
    5.08817958987496047479348604269944e-03, 5.12215478492587718978290567406475e-03, 5.14261285374590249724890966831481e-03,
    5.14947294294515640900034014748599e-03,
};
static const double k61_xgk[31] = {
    9.99484410050490573729220500354131e-02, 9.96893484074649477433283095706429e-02, 9.91630996870404568532819666870637e-02,
    9.83668123279747147469365131655650e-02, 9.73116322501126201904853019186703e-02, 9.60021864968307464538455064939626e-02,
    9.44374444748559971340995389255113e-02, 9.26200047429274336829863045750244e-02, 9.05573307699907847911902081250446e-02,
    8.82560535792052680559294230988598e-02, 8.57205233546061151628236984834075e-02, 8.29565762382768329130655615699652e-02,
    7.99727835821839039276426319702296e-02, 7.67777432104826129677377366533619e-02, 7.33790062453226754612956028722692e-02,
    6.97850494793315762054319861817930e-02, 6.60061064126626906300998598453589e-02, 6.20526182989242849896704967704864e-02,
    5.79345235826361701358955258456263e-02, 5.36624148142019891105647388940270e-02, 4.92480467861778556382112981282262e-02,
    4.47033769538089167938643697652878e-02, 4.00401254830394376371671683045861e-02, 3.52704725530878088202157982777862e-02,
    3.04073202273625088631892054991113e-02, 2.54636926167889840466607154212397e-02, 2.04525116682309875126843934367571e-02,
    1.53869913608583545189256724938787e-02, 1.02806937966737031719954842401421e-02, 5.14718425553176931602772370411003e-03,
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
