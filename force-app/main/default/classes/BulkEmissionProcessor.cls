/**
 * @description Batchable Apex class for processing large volumes of emission records.
 *              Recalculates net emissions in bulk, handles governor limits safely.
 *              Schedulable: runs nightly to process pending emission records.
 * @author      GreenSphere AI
 * @version     1.0
 */
public with sharing class BulkEmissionProcessor implements Database.Batchable<SObject>, Schedulable {

    private Date startDate;
    private Date endDate;
    private Set<Id> accountIds;

    // Constructor for targeted processing
    public BulkEmissionProcessor(Date startDate, Date endDate, Set<Id> accountIds) {
        this.startDate  = startDate;
        this.endDate    = endDate;
        this.accountIds = accountIds;
    }

    // Default constructor for scheduled full run
    public BulkEmissionProcessor() {
        this.startDate  = Date.today().addDays(-30);
        this.endDate    = Date.today();
        this.accountIds = null;
    }

    /**
     * @description Schedulable execute — runs full batch nightly.
     */
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new BulkEmissionProcessor(), 200);
    }

    /**
     * @description Query scope — returns all unprocessed emission records.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT Id, Scope_Type__c, Source_Category__c, ' +
                       'Activity_Value__c, Carbon_Offset__c, Net_Emission__c, ' +
                       'Emission_Date__c, Company__c ' +
                       'FROM Emission_Record__c ' +
                       'WHERE Emission_Date__c >= :startDate ' +
                       'AND Emission_Date__c <= :endDate ';

        if (accountIds != null && !accountIds.isEmpty()) {
            query += 'AND Company__c IN :accountIds ';
        }
        query += 'ORDER BY Emission_Date__c ASC';

        return Database.getQueryLocator(query);
    }

    /**
     * @description Execution chunk — recalculates emissions for each batch.
     */
    public void execute(Database.BatchableContext bc, List<Emission_Record__c> scope) {
        Map<Id, Decimal> calculatedValues = EmissionCalculatorService.calculateEmissions(scope);
        List<Emission_Record__c> toUpdate = new List<Emission_Record__c>();

        for (Emission_Record__c rec : scope) {
            if (calculatedValues.containsKey(rec.Id)) {
                Decimal newValue = calculatedValues.get(rec.Id);
                if (rec.Net_Emission__c != newValue) {
                    toUpdate.add(new Emission_Record__c(
                        Id             = rec.Id,
                        Net_Emission__c = newValue
                    ));
                }
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }

        // Check for threshold alerts on affected accounts
        Set<Id> affectedAccounts = new Set<Id>();
        for (Emission_Record__c rec : scope) {
            if (rec.Company__c != null) affectedAccounts.add(rec.Company__c);
        }
        ESGAlertService.checkAndPublishEmissionAlerts(affectedAccounts);
    }

    /**
     * @description Post-processing — recalculate ESG scores after all batches complete.
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('BulkEmissionProcessor complete. Batch Id: ' + bc.getJobId());
        // Trigger compliance checks
        ESGAlertService.checkComplianceDeadlines();
    }

    /**
     * @description Schedules this job to run nightly at 2 AM.
     * Call this once from anonymous Apex:
     *   BulkEmissionProcessor.scheduleNightly();
     */
    public static void scheduleNightly() {
        String cronExp = '0 0 2 * * ?'; // 2:00 AM daily
        System.schedule('GreenSphere Nightly Emission Processing', cronExp, new BulkEmissionProcessor());
    }
}
