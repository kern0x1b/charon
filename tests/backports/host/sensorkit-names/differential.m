// The port's own values, printed from its own LINKED symbols.
//
// This object is the one tests compile from packages/a/apple-backports/SensorKit/SensorKitNames14.m, so
// every name below resolves to THIS PACKAGE'S definition and not to the host framework's - the port's
// object wins at link time, and the host's values come from the other process, which is what makes the
// two independent.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

extern CFStringRef SRDeviceUsageCategoryBooks;
extern CFStringRef SRDeviceUsageCategoryBusiness;
extern CFStringRef SRDeviceUsageCategoryCatalogs;
extern CFStringRef SRDeviceUsageCategoryDeveloperTools;
extern CFStringRef SRDeviceUsageCategoryEducation;
extern CFStringRef SRDeviceUsageCategoryEntertainment;
extern CFStringRef SRDeviceUsageCategoryFinance;
extern CFStringRef SRDeviceUsageCategoryFoodAndDrink;
extern CFStringRef SRDeviceUsageCategoryGames;
extern CFStringRef SRDeviceUsageCategoryGraphicsAndDesign;
extern CFStringRef SRDeviceUsageCategoryHealthAndFitness;
extern CFStringRef SRDeviceUsageCategoryKids;
extern CFStringRef SRDeviceUsageCategoryLifestyle;
extern CFStringRef SRDeviceUsageCategoryMedical;
extern CFStringRef SRDeviceUsageCategoryMiscellaneous;
extern CFStringRef SRDeviceUsageCategoryMusic;
extern CFStringRef SRDeviceUsageCategoryNavigation;
extern CFStringRef SRDeviceUsageCategoryNews;
extern CFStringRef SRDeviceUsageCategoryNewsstand;
extern CFStringRef SRDeviceUsageCategoryPhotoAndVideo;
extern CFStringRef SRDeviceUsageCategoryProductivity;
extern CFStringRef SRDeviceUsageCategoryReference;
extern CFStringRef SRDeviceUsageCategoryShopping;
extern CFStringRef SRDeviceUsageCategorySocialNetworking;
extern CFStringRef SRDeviceUsageCategorySports;
extern CFStringRef SRDeviceUsageCategoryStickers;
extern CFStringRef SRDeviceUsageCategoryTravel;
extern CFStringRef SRDeviceUsageCategoryUtilities;
extern CFStringRef SRDeviceUsageCategoryWeather;
extern CFStringRef SRSensorAccelerometer;
extern CFStringRef SRSensorAmbientLightSensor;
extern CFStringRef SRSensorDeviceUsageReport;
extern CFStringRef SRSensorKeyboardMetrics;
extern CFStringRef SRSensorMessagesUsageReport;
extern CFStringRef SRSensorOnWristState;
extern CFStringRef SRSensorPedometerData;
extern CFStringRef SRSensorPhoneUsageReport;
extern CFStringRef SRSensorRotationRate;
extern CFStringRef SRSensorVisits;

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    CFStringRef all[] = {
        SRDeviceUsageCategoryBooks, SRDeviceUsageCategoryBusiness, SRDeviceUsageCategoryCatalogs, SRDeviceUsageCategoryDeveloperTools, SRDeviceUsageCategoryEducation, SRDeviceUsageCategoryEntertainment, SRDeviceUsageCategoryFinance, SRDeviceUsageCategoryFoodAndDrink, SRDeviceUsageCategoryGames, SRDeviceUsageCategoryGraphicsAndDesign, SRDeviceUsageCategoryHealthAndFitness, SRDeviceUsageCategoryKids, SRDeviceUsageCategoryLifestyle, SRDeviceUsageCategoryMedical, SRDeviceUsageCategoryMiscellaneous, SRDeviceUsageCategoryMusic, SRDeviceUsageCategoryNavigation, SRDeviceUsageCategoryNews, SRDeviceUsageCategoryNewsstand, SRDeviceUsageCategoryPhotoAndVideo, SRDeviceUsageCategoryProductivity, SRDeviceUsageCategoryReference, SRDeviceUsageCategoryShopping, SRDeviceUsageCategorySocialNetworking, SRDeviceUsageCategorySports, SRDeviceUsageCategoryStickers, SRDeviceUsageCategoryTravel, SRDeviceUsageCategoryUtilities, SRDeviceUsageCategoryWeather, SRSensorAccelerometer, SRSensorAmbientLightSensor, SRSensorDeviceUsageReport, SRSensorKeyboardMetrics, SRSensorMessagesUsageReport, SRSensorOnWristState, SRSensorPedometerData, SRSensorPhoneUsageReport, SRSensorRotationRate, SRSensorVisits
    };
    const char *label[] = {
        "SRDeviceUsageCategoryBooks", "SRDeviceUsageCategoryBusiness", "SRDeviceUsageCategoryCatalogs", "SRDeviceUsageCategoryDeveloperTools", "SRDeviceUsageCategoryEducation", "SRDeviceUsageCategoryEntertainment", "SRDeviceUsageCategoryFinance", "SRDeviceUsageCategoryFoodAndDrink", "SRDeviceUsageCategoryGames", "SRDeviceUsageCategoryGraphicsAndDesign", "SRDeviceUsageCategoryHealthAndFitness", "SRDeviceUsageCategoryKids", "SRDeviceUsageCategoryLifestyle", "SRDeviceUsageCategoryMedical", "SRDeviceUsageCategoryMiscellaneous", "SRDeviceUsageCategoryMusic", "SRDeviceUsageCategoryNavigation", "SRDeviceUsageCategoryNews", "SRDeviceUsageCategoryNewsstand", "SRDeviceUsageCategoryPhotoAndVideo", "SRDeviceUsageCategoryProductivity", "SRDeviceUsageCategoryReference", "SRDeviceUsageCategoryShopping", "SRDeviceUsageCategorySocialNetworking", "SRDeviceUsageCategorySports", "SRDeviceUsageCategoryStickers", "SRDeviceUsageCategoryTravel", "SRDeviceUsageCategoryUtilities", "SRDeviceUsageCategoryWeather", "SRSensorAccelerometer", "SRSensorAmbientLightSensor", "SRSensorDeviceUsageReport", "SRSensorKeyboardMetrics", "SRSensorMessagesUsageReport", "SRSensorOnWristState", "SRSensorPedometerData", "SRSensorPhoneUsageReport", "SRSensorRotationRate", "SRSensorVisits"
    };
    for (size_t i = 0; i < sizeof all / sizeof all[0]; i++) {
        char b[256] = {0};
        if (!all[i] || !CFStringGetCString(all[i], b, sizeof b, kCFStringEncodingUTF8)) {
            printf("PORT\t%s\t(UNREADABLE)\n", label[i]);
            continue;
        }
        printf("PORT\t%s\t%s\n", label[i], b);
    }
    return 0;
}
