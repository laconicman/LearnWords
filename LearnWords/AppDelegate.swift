//
//  AppDelegate.swift
//  LearnWords
//
//  Created by Paul on 08.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        UINavigationBar.appearance().setBackgroundImage(UIImage(named: "navigationBarBackground"), for: .default)
        // Further customization
        UINavigationBar.appearance().tintColor = UIColor.orange
        UITabBar.appearance().tintColor = UIColor.orange
        // UITabBar.appearance().backgroundColor
        // Next lines should do the same, but they don't work for some reasons
//        if let navigationBarBackground = UIImage(named: "navigationBarBackground") {
//            UINavigationBar.appearance().backgroundColor = UIColor(patternImage: navigationBarBackground)
//        }
        //All this is optional. Works fine without this stuff
//        if let path = Bundle.main.path(forResource: "Root", ofType: "plist"),
//            let settingsDict = NSDictionary(contentsOfFile: path) as Dictionary {
//            UserDefaults.standard.register(defaults: settingsDict)
//        }
//        UserDefaults.standard.register(defaults: [:])
//        UserDefaults.standard.synchronize()
        print("UserDefaults.standard.double(forKey: pitchMultiplierPreference) = " + String(UserDefaults.standard.double(forKey: "pitchMultiplierPreference")))
        print("UserDefaults.standard.double(forKey: utteranceRatePreference) = " + String(UserDefaults.standard.double(forKey: "utteranceRatePreference")))
        print("userDefaultsGroup.double(forKey: pitchMultiplierPreference) = " + String(userDefaultsGroup.double(forKey: "pitchMultiplierPreference") ?? 99))
        print("userDefaultsGroup.double(forKey: utteranceRatePreference) = " + String(userDefaultsGroup.double(forKey: "utteranceRatePreference") ?? 99))
        //print(UserDefaults.standard.setValue((10.0 as Any), forKeyPath: "pitchMultiplierPreference\MaximumValue"))
        //Experiments with Settings register() method
        //print(LWUserDefaults.standard.utteranceRatePreference)
        //print(LWUserDefaults.standard.pitchMultiplierPreference)
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}

