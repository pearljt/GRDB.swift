import UIKit
import GRDB

class MasterViewController: UITableViewController, FetchedRecordsControllerDelegate {
    var detailViewController: DetailViewController? = nil
    var fetchedRecordsController: FetchedRecordsController<Person>!
    var persons = [Person]()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.leftBarButtonItem = self.editButtonItem()
        if let split = self.splitViewController {
            let controllers = split.viewControllers
            self.detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
        }
        
        fetchedRecordsController = FetchedRecordsController(sql: "SELECT * FROM persons ORDER BY LOWER(firstName), LOWER(lastName)", databaseQueue: dbQueue)
        fetchedRecordsController.delegate = self
        fetchedRecordsController.performFetch()
        tableView.reloadData()
    }

    override func viewWillAppear(animated: Bool) {
        self.clearsSelectionOnViewWillAppear = self.splitViewController!.collapsed
        super.viewWillAppear(animated)
    }
    
    
    // MARK: - Segues
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "showPerson" {
            let person = fetchedRecordsController.recordAtIndexPath(self.tableView.indexPathForSelectedRow!)
            let detailViewController = (segue.destinationViewController as! UINavigationController).topViewController as! DetailViewController
            detailViewController.person = person
            detailViewController.navigationItem.leftBarButtonItem = self.splitViewController?.displayModeButtonItem()
            detailViewController.navigationItem.leftItemsSupplementBackButton = true
        }
        else if segue.identifier == "editNewPerson" {
            let personEditionViewController = (segue.destinationViewController as! UINavigationController).topViewController as! PersonEditionViewController
            personEditionViewController.person = Person()
        }
    }
    
    // Unwind action: commit person edition
    @IBAction func commitPersonEdition(segue: UIStoryboardSegue) {
        let personEditionViewController = segue.sourceViewController as! PersonEditionViewController
        let person = personEditionViewController.person
        
        // Ignore person with no name
        guard (person.firstName ?? "").characters.count > 0 || (person.lastName ?? "").characters.count > 0 else {
            return
        }
        
        // Save person
        try! dbQueue.inDatabase { db in
            try person.save(db)
        }
    }
    
    
    // MARK: - Table View
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let persons = fetchedRecordsController.fetchedRecords {
            return persons.count
        }
        return 0
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)

        let person = fetchedRecordsController.recordAtIndexPath(indexPath)!
        cell.textLabel!.text = person.fullName
        return cell
    }

    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        // Delete the person
        let person = fetchedRecordsController.recordAtIndexPath(indexPath)!
        try! dbQueue.inTransaction { db in
            try person.delete(db)
            return .Commit
        }
    }
    
    // MARK: - FetchedRecordsControllerDelegate
    
    func controllerWillUpdate<T>(controller: FetchedRecordsController<T>) {
        tableView.beginUpdates()
    }
    
    func controllerUpdate<T>(controller: FetchedRecordsController<T>, update: FetchedRecordsUpdate<T>) {
        switch update {
        case .Inserted(_, let at):
            tableView.insertRowsAtIndexPaths([at], withRowAnimation: .Automatic)
            
        case .Deleted(_, let from):
            tableView.deleteRowsAtIndexPaths([from], withRowAnimation: .Automatic)
            
        case .Moved(_, let from, let to):
            tableView.moveRowAtIndexPath(from, toIndexPath: to)
            
        case .Updated(_, let at, let changes):
            if let changes = changes {
                let columns = ["firstName", "lastName"]
                for (key, _) in changes {
                    if columns.contains(key) {
                        tableView.reloadRowsAtIndexPaths([at], withRowAnimation: .Automatic)
                        break
                    }
                }
            } else {
                tableView.reloadRowsAtIndexPaths([at], withRowAnimation: .Automatic)
            }
        }
    }
    
    func controllerDidFinishUpdates<T>(controller: FetchedRecordsController<T>) {
        tableView.endUpdates()
    }
}

