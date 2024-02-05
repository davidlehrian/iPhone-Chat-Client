//
//  ViewController.swift
//  ChatClientSwift
//
//  Created by David Lehrian on 2/3/24.
//

import UIKit
import Network

class ViewController: UIViewController , UITextFieldDelegate{
    @IBOutlet weak var chatSessionTextView: UITextView!
    @IBOutlet weak var sendTextField: UITextField!
    var movementDistance: CGFloat = 0;
    var observer,observer2: NSObjectProtocol?;
    var connection: NWConnection?;
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        chatSessionTextView.text = nil;
        func batteryLevelChanged(notification: Notification) {
            // do something useful with this information
        }
        
        observer = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil, queue: OperationQueue.main,
            using: { (notification: Notification) -> Void in
                if (self.movementDistance == 0){
                    guard let userInfo = notification.userInfo,
                          let keyboardSize = userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect else { return }
                    self.movementDistance = keyboardSize.size.height;
                }
                self.animateTextField(textField: self.sendTextField, up: true);
            })
        observer2 = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidHideNotification,
            object: nil, queue: OperationQueue.main,
            using: { (Notification) -> Void in
                self.animateTextField(textField: self.sendTextField, up: false);
            })
        self.sendTextField.delegate = self;
                
        // use bonjour to find service being advertised on local area network
        let bonjourTCP = NWBrowser.Descriptor.bonjour(type: "_ChatServer._tcp." , domain: "local.")
        let bonjourParms = NWParameters.init()
        let browser = NWBrowser(for: bonjourTCP, using: bonjourParms)
        browser.browseResultsChangedHandler = { ( results, changes ) in
            // process browser results and cancel the browser
            browser.cancel()
            for result in results {
                // take the endpoint and create a connection
                self.connection = NWConnection(to: result.endpoint, using: .tcp)
                // set the stateUpdateHandler on the connection
                self.connection!.stateUpdateHandler = { newState in
                    switch newState {
                    case .ready:
                        print("ready")
                        // this allows me to get host ip and port number if I want it
                        //if let innerEndpoint = self.connection!.currentPath?.remoteEndpoint, case .hostPort(let host, let port) = innerEndpoint {
                        //}
                        // when the connection is ready dispatch an async thread to receive the content from the socket
                        DispatchQueue.global(qos: .userInitiated).async {
                            self.connection!.receive(minimumIncompleteLength: 1, maximumLength: 10000) { content, _, _, _ in
                                if let content = content {
                                    // here is the key, in the completion block call the method to process the data.
                                    self.processReceiveData(content: content, connection: self.connection!)
                                }
                            }
                        }
                    case .setup:
                        print("setup")
                    case .waiting:
                        print("waiting")
                    case .preparing:
                        print("preparing")
                    case .cancelled:
                        print("cancelled")
                    case .failed:
                        print("failed")
                    @unknown default:
                        print("default")
                    }
                }
                // start the connection and process the results in the stateUpdateHandler above
                self.connection!.start(queue: DispatchQueue.main)
                // print some logging information about the result of the browser search
                print("result ", result );
                if case .service(let service) = result.endpoint {
                    print("bonjourA ",service.name)
                }
            }
        }
        browser.start(queue: DispatchQueue.main)
    }
    
    // this method is the called from the completion handler for the connection.receive method
    func processReceiveData(content: Data, connection: NWConnection){
        print(String(data: content, encoding: .utf8)!)
        // I'm updating a textView with the data received so dispatch this on the main queue async
        DispatchQueue.main.async {
            self.appendToChatSession(text: String(data: content, encoding: .utf8)!.trimmingCharacters(in: .newlines))
            // here is the key, call receive again and use this method to process the received content so the
            // receive method is called again. 
            self.connection?.receive(minimumIncompleteLength: 1, maximumLength: 10000) { content, _, _, _ in
                if let content = content {
                    self.processReceiveData(content: content, connection: self.connection!)
                }
            }
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(observer!)
        NotificationCenter.default.removeObserver(observer2!)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool{
        self.sendText(textField);
        return false;
    }
        
    @IBAction func sendText(_ sender: Any) {
        let string = self.sendTextField.text! + "\n"
        self.connection?.send(content: string.data(using: .utf8), completion: .contentProcessed( { error in
            if let error = error {
                print("Error: %@",error)
                return
            }
        }))
        self.appendToChatSession(text: self.sendTextField.text!)
        self.sendTextField.text=""
    }
    
    func appendToChatSession( text: String){
        var localText :String = text;
        if (localText.count == 0) {
            return;
        }
        if (localText.count != 0){
            localText = String.localizedStringWithFormat("%@%@%@",self.chatSessionTextView.text,"\n",text);
        }
        self.chatSessionTextView.attributedText = attributedStringFromString(aString: localText);
        let bottom = NSMakeRange(self.chatSessionTextView.text.count - 1, 1);
        self.chatSessionTextView.scrollRangeToVisible(bottom);
    }
    
    func animateTextField(textField: UITextField, up: Bool){
        let movement = (up ? self.movementDistance : -self.movementDistance);
        UIView.animate(withDuration: 0.2, animations: {
            self.view.frame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y, self.view.frame.size.width, self.view.frame.size.height-movement)
        });
        DispatchQueue.main.async {
            let bottom = NSMakeRange(self.chatSessionTextView.text.count - 1, 0);
            self.chatSessionTextView.scrollRangeToVisible(bottom);
        }
    }
}

func attributedStringFromString(aString: String) -> NSAttributedString{
    let range = NSMakeRange(0, aString.count)
    let mutableAttributedString = NSMutableAttributedString.init(string: aString)
    mutableAttributedString.addAttribute(NSAttributedString.Key.font, value: UIFont.init(name: "Arial", size:20)!, range: range)
    // This is to support dark mode otherwise the text will be black. This changes it to be the dynamic color UIColor.labelColor
    // if the color is currently black. The text that is displayed in red, green and blue will remain that color. DML 1/10/2024
    if #available(iOS 13.0, *) {
        mutableAttributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.label, range: range)
    }
    return mutableAttributedString
}
