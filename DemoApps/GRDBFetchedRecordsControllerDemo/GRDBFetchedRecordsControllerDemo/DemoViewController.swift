import UIKit

class DemoViewController: UITableViewController {
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(true)
        navigationController?.toolbarHidden = true
        navigationItem.backBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Demo", comment: ""), style: .Plain, target: nil, action: nil)
    }
}
