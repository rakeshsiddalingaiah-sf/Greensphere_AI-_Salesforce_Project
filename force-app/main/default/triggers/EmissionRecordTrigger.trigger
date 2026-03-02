/**
 * @description Trigger on Emission_Record__c.
 *              Delegates to EmissionTriggerHandler for all logic.
 *              Follows trigger handler pattern for maintainability.
 */
trigger EmissionRecordTrigger on Emission_Record__c (before insert, before update, after insert, after update) {
    EmissionTriggerHandler handler = new EmissionTriggerHandler();

    switch on Trigger.operationType {
        when BEFORE_INSERT {
            handler.onBeforeInsert(Trigger.new);
        }
        when BEFORE_UPDATE {
            handler.onBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
        when AFTER_INSERT {
            handler.onAfterInsert(Trigger.new);
        }
        when AFTER_UPDATE {
            handler.onAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
