/**
 * @description Real-time ESG alert service using Platform Events.
 *              Publishes ESG_Alert__e events when emission thresholds are breached,
 *              compliance deadlines approach, or supplier risk scores spike.
 * @author      GreenSphere AI
 * @version     1.0
 */
public with sharing class ESGAlertService {

    public enum AlertType {
        EMISSION_THRESHOLD_BREACH,
        COMPLIANCE_DEADLINE_APPROACHING,
        SUPPLIER_RISK_HIGH,
        ESG_SCORE_DECLINE,
        REGULATION_UPDATE
    }

    /**
     * @description Publishes a Platform Event alert for ESG threshold breach.
     * @param alertType Type of alert
     * @param accountId Affected account
     * @param message   Alert message
     * @param severity  Critical / High / Medium / Low
     */
    public static void publishAlert(AlertType alertType, Id accountId, String message, String severity) {
        ESG_Alert__e alert = new ESG_Alert__e();
        alert.Alert_Type__c     = alertType.name();
        alert.Account_Id__c     = String.valueOf(accountId);
        alert.Message__c        = message;
        alert.Severity__c       = severity;
        alert.Alert_Timestamp__c = DateTime.now();

        Database.SaveResult result = EventBus.publish(alert);
        if (!result.isSuccess()) {
            System.debug('Failed to publish ESG Alert: ' + result.getErrors()[0].getMessage());
        }
    }

    /**
     * @description Checks emission records and fires alerts if thresholds are breached.
     *              Called by trigger or scheduled job.
     * @param accountIds Set of Account Ids to check
     */
    public static void checkAndPublishEmissionAlerts(Set<Id> accountIds) {
        List<ESG_Regulation_Threshold__mdt> thresholds = [
            SELECT Regulation_Code__c, Max_Emission_Tonnes__c, Alert_Threshold_Pct__c
            FROM ESG_Regulation_Threshold__mdt
            WHERE IsActive__c = true
            LIMIT 10
        ];

        Date startOfYear = Date.newInstance(Date.today().year(), 1, 1);

        for (Id accountId : accountIds) {
            EmissionCalculatorService.ESGEmissionSummary summary =
                EmissionCalculatorService.getEmissionSummary(accountId, startOfYear, Date.today());

            for (ESG_Regulation_Threshold__mdt threshold : thresholds) {
                if (threshold.Max_Emission_Tonnes__c != null && summary.grandTotal > 0) {
                    Decimal alertAt = threshold.Max_Emission_Tonnes__c *
                        (threshold.Alert_Threshold_Pct__c != null ? threshold.Alert_Threshold_Pct__c / 100 : 0.9);

                    if (summary.grandTotal >= threshold.Max_Emission_Tonnes__c) {
                        publishAlert(
                            AlertType.EMISSION_THRESHOLD_BREACH,
                            accountId,
                            'CRITICAL: Emissions (' + summary.grandTotal.setScale(1) + ' tCO2e) have EXCEEDED the ' +
                            threshold.Regulation_Code__c + ' threshold of ' + threshold.Max_Emission_Tonnes__c + ' tCO2e.',
                            'Critical'
                        );
                    } else if (summary.grandTotal >= alertAt) {
                        publishAlert(
                            AlertType.EMISSION_THRESHOLD_BREACH,
                            accountId,
                            'WARNING: Emissions (' + summary.grandTotal.setScale(1) + ' tCO2e) are approaching the ' +
                            threshold.Regulation_Code__c + ' threshold of ' + threshold.Max_Emission_Tonnes__c + ' tCO2e.',
                            'High'
                        );
                    }
                }
            }
        }
    }

    /**
     * @description Fires alerts for compliance records approaching their due dates.
     */
    public static void checkComplianceDeadlines() {
        Date warningDate = Date.today().addDays(30);

        List<Compliance_Record__c> upcoming = [
            SELECT Id, Company__c, Regulation__c, Due_Date__c, Status__c
            FROM Compliance_Record__c
            WHERE Due_Date__c <= :warningDate
              AND Due_Date__c >= :Date.today()
              AND Status__c != 'Completed'
        ];

        for (Compliance_Record__c rec : upcoming) {
            Integer daysLeft = Date.today().daysBetween(rec.Due_Date__c);
            String severity  = daysLeft <= 7 ? 'Critical' : daysLeft <= 14 ? 'High' : 'Medium';

            publishAlert(
                AlertType.COMPLIANCE_DEADLINE_APPROACHING,
                rec.Company__c,
                'Compliance deadline for ' + rec.Regulation__c + ' is in ' + daysLeft + ' days. Status: ' + rec.Status__c,
                severity
            );
        }
    }

    /**
     * @description Fires high supplier risk alerts.
     * @param supplierResults List of SupplierRiskService results
     */
    public static void checkSupplierRiskAlerts(List<SupplierRiskService.SupplierRiskResult> supplierResults) {
        for (SupplierRiskService.SupplierRiskResult res : supplierResults) {
            if (res.riskLevel == 'High') {
                publishAlert(
                    AlertType.SUPPLIER_RISK_HIGH,
                    res.supplierId,
                    'Supplier ' + res.supplierName + ' has a HIGH ESG risk score of ' +
                    res.riskScore + '. Compliance Status: ' + res.complianceStatus,
                    'High'
                );
            }
        }
    }
}
