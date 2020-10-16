//
//  ActionViewController.swift
//  ImportAsDictAction
//
//  Created by  Paul on 08.07.2020.
//  Copyright © 2020 Paul. All rights reserved.
//

import UIKit
import MobileCoreServices

class ActionViewController: UIViewController {

    @IBOutlet weak var textView: UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()
    
        // Get the item[s] we're handling from the extension context.
        
        var textFound = false
        for item in self.extensionContext!.inputItems as! [NSExtensionItem] {
            for provider in item.attachments! {
                if provider.hasItemConformingToTypeIdentifier(kUTTypePlainText as String) {
                    // This is a text.
                    weak var weakTextView = self.textView
                    provider.loadItem(forTypeIdentifier: kUTTypePlainText as String, options: nil, completionHandler: { (textItem, error) in
                        OperationQueue.main.addOperation {
                            if let strongTextView = weakTextView {
                                if let gotText = textItem as? String {
                                    strongTextView.text = gotText
                                    // parse as dict
                                }
                            }
                        }
                    })
                    
                    textFound = true
                    break
                }
            }
            
            if (textFound) {
                // We only handle one text, so stop looking for more.
                break
            }
        }
    }

    @IBAction func done() {
        // Return any edited content to the host app.
        // This template doesn't do anything, so we just echo the passed in items.

        self.extensionContext!.completeRequest(returningItems: self.extensionContext!.inputItems, completionHandler: nil)
    }

    @IBAction func openApp(_ sender: Any) {
                self.extensionContext?.open(URL(string: UIApplication.openSettingsURLString)!, completionHandler: nil)
    }
}
