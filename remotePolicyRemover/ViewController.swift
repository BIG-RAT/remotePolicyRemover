//
//  ViewController.swift
//  remotePolicyRemover
//
//  Created by Leslie Helou on 11/30/18.
//  Copyright © 2018 jamf. All rights reserved.
//

import Cocoa

class ViewController: NSViewController, NSTextFieldDelegate, URLSessionDelegate {

    @IBOutlet weak var jamfServer_TextField: NSTextField!
    @IBOutlet weak var username_TextField: NSTextField!
    @IBOutlet weak var password_TextFiled: NSSecureTextField!
    
    @IBOutlet weak var remotePolicyCount_TextField: NSTextField!
    @IBOutlet weak var oldestPolicy_TextField: NSTextField!
    @IBOutlet weak var cutoffDate_TextField: NSTextField!
    
    @IBOutlet weak var spinner: NSProgressIndicator!
    
    let theOpQ = OperationQueue() // create operation queue for API calls
    
    var serverURL         = ""
    var username          = ""
    var password          = ""
    var userCreds         = ""
    var userBase64Creds   = ""
    var policyIdNamdDict:[Int:Double] = [:]   // something like policyId, epoch of policy
    var oldestRemotePolicyEpoch  = NSDate().timeIntervalSince1970
    var oldestRemotePolicyString = ""
    var policyCutOffDate         = ""
    var policyCutOffEpoch:Double = 0.0
    var currentPolicyCount       = 0
    
    var monthString = ""
    var dayString   = ""
    
    var remotePolicyList  = [String]()
    var remotePolicyCount:Int16 = 0
    var httpStatusCode: Int = 0
    
    let userDefaults = UserDefaults.standard
    
    @IBAction func fetch_Button(_ sender: Any) {
        remotePolicyCount = 0
        policyIdNamdDict.removeAll()
        remotePolicyCount_TextField.stringValue = ""
        oldestPolicy_TextField.stringValue      = ""
        oldestRemotePolicyString                = ""
        cutoffDate_TextField.stringValue        = ""
        oldestRemotePolicyEpoch                 = NSDate().timeIntervalSince1970
        
        username = self.username_TextField.stringValue
        password = self.password_TextFiled.stringValue
        
        userCreds = "\(username):\(password)"
        userBase64Creds = userCreds.data(using: .utf8)?.base64EncodedString() ?? ""
        
        spinner.startAnimation(self)
        
        getEndpoints(endpoint: "policies") {
            (result: String) in
            print("done")
        }

    }
    @IBAction func clear_Button(_ sender: Any) {
        
        policyCutOffDate = cutoffDate_TextField.stringValue
        if policyCutOffDate != "" {
            policyCutOffEpoch = toEpochTime(dateString: policyCutOffDate)
            print("policyCutOffEpoch: \(policyCutOffEpoch)")
            if policyCutOffEpoch < 0.0 {
                alert_dialog(header: "Alert:", message: "Invalid date.  Use YYYY-MM-DD")
                return
            }
        } else {
            policyCutOffEpoch = 0.0
        }

        spinner.startAnimation(self)
        
        for (id, epoch) in policyIdNamdDict {
            currentPolicyCount += 1
//            print("checking policy id: \(id) \t epoch: \(epoch)")
            if (epoch < policyCutOffEpoch) || (policyCutOffEpoch == 0.0) {
//                print("\tremoving policy id: \(id) \t epoch: \(epoch)")
                RemoveRemotePolicies(endpointType: "policy", policyId: id, policyName: "", currentPolicy: currentPolicyCount, policyCount: policyIdNamdDict.count)
            } else if currentPolicyCount == policyIdNamdDict.count {
                RemoveRemotePolicies(endpointType: "policy", policyId: 0, policyName: "", currentPolicy: currentPolicyCount, policyCount: policyIdNamdDict.count)
            }
        }   // for (id, epoch) - end
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            switch textField.tag {
            case 0:
                userDefaults.set(jamfServer_TextField.stringValue, forKey: "jamfServer")
            case 1:
                userDefaults.set(username_TextField.stringValue, forKey: "username")
            default:
                break
            }
        }
    }
    @IBAction func quit_Button(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        jamfServer_TextField.stringValue  = userDefaults.string(forKey: "jamfServer") ?? "https://<server>.jamfcloud.com"
        username_TextField.stringValue    = userDefaults.string(forKey: "username") ?? ""
        
        // configure TextField so that we can monitor when editing is done
        self.jamfServer_TextField.delegate = self
        self.username_TextField.delegate   = self
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
        
    func getEndpoints(endpoint: String, completion: @escaping (_ result: String) -> Void) {
        print("Getting \(endpoint)")
        theOpQ.maxConcurrentOperationCount = 1
        let semaphore = DispatchSemaphore(value: 0)
        
        self.serverURL = "\(self.jamfServer_TextField.stringValue)/JSSResource/\(endpoint)"
//        print("initial URL: \(self.serverURL)\n")
        self.serverURL = self.serverURL.replacingOccurrences(of: "//JSSResource", with: "/JSSResource")
//        print("URL: \(self.serverURL)\n")
        
        theOpQ.addOperation {
            let encodedURL = NSURL(string: self.serverURL)
            let request = NSMutableURLRequest(url: encodedURL! as URL)
            request.httpMethod = "GET"
            let configuration = URLSessionConfiguration.default
            configuration.httpAdditionalHeaders = ["Authorization" : "Basic \(self.userBase64Creds)", "Content-Type" : "application/json", "Accept" : "application/json"]
            let session = Foundation.URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
            let task = session.dataTask(with: request as URLRequest, completionHandler: {
                (data, response, error) -> Void in
                if let httpResponse = response as? HTTPURLResponse {
//                    print("httpResponse: \(String(describing: response))")

                    let json = try? JSONSerialization.jsonObject(with: data!, options: .allowFragments)
                        if let endpointJSON = json as? [String: Any] {
//                            print("endpointJSON: \(endpointJSON))")
                            print("\n-------- Getting all \(endpoint) --------")

                                print("processing policies")
                                if let endpointInfo = endpointJSON[endpoint] as? [Any] {
                                    let policyCount: Int = endpointInfo.count
                                    print("\(endpoint) found: \(policyCount)")
                                    
                                    if policyCount > 0 {
                                        for i in (0..<policyCount) {
                                            let record = endpointInfo[i] as! [String : AnyObject]
                                            let xmlID: Int = (record["id"] as! Int)
                                            let xmlName: String = (record["name"] as! String)
                                            //print("\(xmlName)")
                                            self.remotePolicyList.append(xmlName)
//                                            let regexSearch = try! NSRegularExpression(pattern: "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] at", options:.caseInsensitive)
                                            
                                            if let _ = xmlName.range(of:"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] at", options: .regularExpression) {
//                                                let result = xmlName.substring(with:range)
//                                                print("\tresult: \(xmlName)")
                                                self.remotePolicyCount += 1
                                                DispatchQueue.main.async {
                                                    self.remotePolicyCount_TextField.stringValue = "\(self.remotePolicyCount)"
                                                }
                                                let currentPolicyDate = self.toEpochTime(dateString: xmlName)
                                                self.policyIdNamdDict[xmlID] = currentPolicyDate
//                                                usleep(300000)
                                                
                                            }
                                        }
                                    }   // end if let buildings, departments...
                                    
//                                    print("\(self.policyIdNamdDict)")
                                    self.oldestPolicy_TextField.stringValue = "\(String(describing: self.oldestRemotePolicyString))"
                                    self.spinner.stopAnimation(self)
                                    
                                }   //if let endpointInfo = endpointJSON - end
  
                        }   // if let endpointJSON - end
                    
                    
                    if httpResponse.statusCode >= 199 && httpResponse.statusCode <= 299 {
                        //print(httpResponse.statusCode)
                    } else {
                        // something went wrong
                        //self.writeToHistory(stringOfText: "**** \(self.getName(endpoint: endpointType, objectXML: endPointXML)) - Failed\n")
//                        print("\n\n---------- status code ----------")
//                        print(httpResponse.statusCode)
//                        self.httpStatusCode = httpResponse.statusCode
//                        print("---------- status code ----------")
//                        print("\n\n---------- response ----------")
//                        print(httpResponse)
//                        print("---------- response ----------\n\n")
                        switch self.httpStatusCode {
                        case 401:
                            Alert().display(header: "Authentication Failure", message: "Please verify username and password for the server.")
                        default:
                            Alert().display(header: "Error", message: "The following error was returned: \(self.httpStatusCode).")
                        }
                        
                        //                        401 - wrong username and/or password
                        //                        409 - unable to create object; already exists or data missing or xml error
                        //                        self.go_button.isEnabled = true
                        self.spinner.stopAnimation(self)
                        return
                        
                    }   // if httpResponse/else - end
                }   // if let httpResponse - end
                semaphore.signal()
                if error != nil {
                }
            })  // let task = session - end
            //print("GET")
            task.resume()
            semaphore.wait()
        }   // theOpQ - end
        
        completion("Got endpoint - \(endpoint)")
    }
    
    func RemoveRemotePolicies(endpointType: String, policyId: Int, policyName: String, currentPolicy: Int, policyCount: Int) {
        // this is where we delete the endpoint
        var removeDestUrl = ""
        theOpQ.maxConcurrentOperationCount = 3
        let semaphore = DispatchSemaphore(value: 0)
        
        if policyName != "All Managed Clients" && policyName != "All Managed Servers" && policyName != "All Managed iPads" && policyName != "All Managed iPhones" && policyName != "All Managed iPod touches" {
            
            removeDestUrl = "\(self.jamfServer_TextField.stringValue)/JSSResource/policies/id/\(policyId)"
            removeDestUrl = removeDestUrl.replacingOccurrences(of: "//JSSResource", with: "/JSSResource")
            
            theOpQ.addOperation {
                
                let encodedURL = NSURL(string: removeDestUrl)
                let request = NSMutableURLRequest(url: encodedURL! as URL)
                request.httpMethod = "DELETE"
                let configuration = URLSessionConfiguration.default
                configuration.httpAdditionalHeaders = ["Authorization" : "Basic \(self.userBase64Creds)", "Content-Type" : "text/xml", "Accept" : "text/xml"]
                //request.httpBody = encodedXML!
                let session = Foundation.URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
                let task = session.dataTask(with: request as URLRequest, completionHandler: {
                    (data, response, error) -> Void in
                    if let httpResponse = response as? HTTPURLResponse {
                        //print(httpResponse.statusCode)
                        //print(httpResponse)
                        DispatchQueue.main.async {
//                            self.migrationStatus(endpoint: endpointType, count: policyCount)
//                            self.objects_completed_field.stringValue = "\(currentPolicy)"
//                            print("[RemoveEndpoints] Removing \(endpointType)\n")
                        }
                        if httpResponse.statusCode >= 199 && httpResponse.statusCode <= 299 {
//                            print("\t[RemoveEndpoints] \(policyName)\n")
                            self.remotePolicyCount -= 1
                            self.policyIdNamdDict.removeValue(forKey: policyId)
                            DispatchQueue.main.async {
                                self.remotePolicyCount_TextField.stringValue = "\(self.remotePolicyCount)"
                            }
//                            self.POSTsuccessCount += 1
                        } else {
                            print("[RemoveEndpoints] **** Failed to remove: \(policyName)\n")

                        }   // if httpResponse.statusCode - end
                    }   // if let httpResponse - end

                        
                    if currentPolicy == policyCount {
                        self.spinner.stopAnimation(self)

                    }
                    semaphore.signal()
                })  // let task = session.dataTask - end
                task.resume()
                semaphore.wait()
            }   // theOpQ.addOperation - end
        }
    }   // func RemoveRemotePolicies - end
    
    func toEpochTime(dateString: String) -> Double {
//        var myDate = ""
        var epochTime:Double = 0.0
        
        if dateString != "" {
            var policyDate = DateComponents()
            var indexStartOfText = dateString.index(dateString.startIndex, offsetBy: 0)
            var indexEndOfText = dateString.index(dateString.startIndex, offsetBy: 4)
            if case policyDate.year = Int(dateString[indexStartOfText..<indexEndOfText]) {
                //                print("invalid year")
                return(-10.0)
            } else {
                policyDate.year = Int(dateString[indexStartOfText..<indexEndOfText])
            }
//            print("year: \(String(describing: policyDate.year!))")
            
            indexStartOfText = dateString.index(dateString.startIndex, offsetBy: 5)
            indexEndOfText = dateString.index(dateString.startIndex, offsetBy: 7)
            if case policyDate.month = Int(dateString[indexStartOfText..<indexEndOfText]) {
                //                print("invalid month")
                return(-10.0)
            } else {
                policyDate.month = Int(dateString[indexStartOfText..<indexEndOfText])
            }
//            print("month: \(String(describing: policyDate.month!))")
            
            indexStartOfText = dateString.index(dateString.startIndex, offsetBy: 8)
            indexEndOfText = dateString.index(dateString.startIndex, offsetBy: 10)
            if case policyDate.day = Int(dateString[indexStartOfText..<indexEndOfText]) {
//                print("invalid day")
                return(-10.0)
            } else {
                policyDate.day = Int(dateString[indexStartOfText..<indexEndOfText])
                
            }
//            print("day: \(String(describing: policyDate.day!))")
            
            
            let dD = Calendar.current.date(from: policyDate)!
            epochTime = dD.timeIntervalSince1970
//            print("epochTime: \(epochTime)")
            
            // find the oldest policy date
            if epochTime < oldestRemotePolicyEpoch {
                oldestRemotePolicyEpoch = epochTime
                if policyDate.month! < 10 {
                    monthString = "0\(policyDate.month!)"
                } else {
                    monthString = "\(policyDate.month!)"
                }
                if policyDate.day! < 10 {
                    dayString = "0\(policyDate.day!)"
                } else {
                    dayString = "\(policyDate.day!)"
                }
                oldestRemotePolicyString = "\(String(describing: policyDate.year!))-\(monthString)-\(dayString)"
            }
            
        }
        return(epochTime)
    }
    
    func alert_dialog(header: String, message: String) {
        let dialog: NSAlert = NSAlert()
        dialog.messageText = header
        dialog.informativeText = message
        dialog.alertStyle = NSAlert.Style.warning
        dialog.addButton(withTitle: "OK")
        dialog.runModal()
    }   // func alert_dialog - end
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping(  URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
    }
}

