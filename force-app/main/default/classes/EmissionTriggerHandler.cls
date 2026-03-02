/**
 * @description Trigger handler for Emission_Record__c.
 *              Handles emission calculation on save and alert publishing.
 * @author      GreenSphere AI
 */
public with sharing class EmissionTriggerHandler {

    public void onBeforeInsert(List<Emission_Record__c> newRecords) {
        // Validate required fields and set defaults
        for (Emission_Record__c rec : newRecords) {
            if (rec.Carbon_Offset__c == null) rec.Carbon_Offset__c = 0;
            if (rec.Emission_Date__c == null)  rec.Emission_Date__c = Date.today();
        }
    }

    public void onBeforeUpdate(List<Emission_Record__c> newRecords, Map<Id, Emission_Record__c> oldMap) {
        // Recalculate if activity value or offset changed
        List<Emission_Record__c> changed = new List<Emission_Record__c>();
        for (Emission_Record__c rec : newRecords) {
            Emission_Record__c old = oldMap.get(rec.Id);
            if (rec.Activity_Value__c != old.Activity_Value__c ||
                rec.Carbon_Offset__c  != old.Carbon_Offset__c  ||
                rec.Source_Category__c != old.Source_Category__c) {
                changed.add(rec);
            }
        }
        if (!changed.isEmpty()) {
            Map<Id, Decimal> calculated = EmissionCalculatorService.calculateEmissions(changed);
            for (Emission_Record__c rec : newRecords) {
                if (calculated.containsKey(rec.Id)) {
                    rec.Net_Emission__c = calculated.get(rec.Id);
                }
            }
        }
    }

    public void onAfterInsert(List<Emission_Record__c> newRecords) {
        // Calculate net emission for new records (need IDs)
        EmissionCalculatorService.processAndSaveEmissions(newRecords);

        // Check alert thresholds
        Set<Id> accountIds = new Set<Id>();
        for (Emission_Record__c rec : newRecords) {
            if (rec.Company__c != null) accountIds.add(rec.Company__c);
        }
        if (!accountIds.isEmpty()) {
            ESGAlertService.checkAndPublishEmissionAlerts(accountIds);
        }
    }

    public void onAfterUpdate(List<Emission_Record__c> newRecords, Map<Id, Emission_Record__c> oldMap) {
        Set<Id> accountIds = new Set<Id>();
        for (Emission_Record__c rec : newRecords) {
            if (rec.Company__c != null) accountIds.add(rec.Company__c);
        }
        if (!accountIds.isEmpty()) {
            ESGAlertService.checkAndPublishEmissionAlerts(accountIds);
        }
    }
}
