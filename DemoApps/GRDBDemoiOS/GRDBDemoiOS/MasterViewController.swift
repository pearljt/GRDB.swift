import UIKit

class MasterViewController: UITableViewController {
    var detailViewController: DetailViewController? = nil
    var persons = [Person]()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.leftBarButtonItem = self.editButtonItem()
        if let split = self.splitViewController {
            let controllers = split.viewControllers
            self.detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
        }
    }

    override func viewWillAppear(animated: Bool) {
        // Reload persons, and the tableView
        reloadPersons()
        tableView.reloadData()
        
        self.clearsSelectionOnViewWillAppear = self.splitViewController!.collapsed
        super.viewWillAppear(animated)
    }
    
    func reloadPersons() {
        persons = dbQueue.inDatabase { db in
            Person.order(Col.firstName, Col.lastName).fetchAll(db)
        }
    }
    
    
    // MARK: - Segues
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "showPerson" {
            let detailViewController = (segue.destinationViewController as! UINavigationController).topViewController as! DetailViewController
            detailViewController.person = persons[self.tableView.indexPathForSelectedRow!.row]
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
        
        // Reload persons, and insert a cell.
        reloadPersons()
        let index = persons.indexOf { $0.id == person.id }!
        tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: index, inSection: 0)], withRowAnimation: .Automatic)
    }
    
    
    // MARK: - Table View
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return persons.count
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)

        let person = persons[indexPath.row]
        cell.textLabel!.text = person.fullName
        return cell
    }

    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        // Delete the person
        let person = persons[indexPath.row]
        try! dbQueue.inTransaction { db in
            try person.delete(db)
            return .Commit
        }
        persons.removeAtIndex(indexPath.row)
        tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
    }


}

