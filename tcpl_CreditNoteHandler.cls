/**
 * @description       : 
 * @author            : Sumit
 * @group             : 
 * @last modified on  : 08-17-2024
 * @last modified by  : Sumit
**/
public with sharing class tcpl_CreditNoteHandler extends tcpl_TriggerHandlerBase {
	public override void handleBeforeInsert(){
      //Added by Bopanna - 20-1-2026
      UtilityClass.setReasonForChangeValue(trigger.new, null);
        //tcpl_CreditNoteHelper.getNamingConvention((List<Credit_Note__c>)trigger.new);
    }

    public override void handleBeforeUpdate()
    {
      //Added by Bopanna - 20-1-2026
      UtilityClass.setReasonForChangeValue(trigger.new, trigger.oldMap);
        
      List<Credit_Note__c> recordsToUpdateExtId = new List<Credit_Note__c>();
      for (Integer i = 0; i < Trigger.new.size(); i++) {
          Credit_Note__c newRec = (Credit_Note__c) Trigger.new[i];
          Credit_Note__c oldRec = (Credit_Note__c) Trigger.oldMap.get(newRec.Id);

          if (newRec.Name != oldRec.Name) {
              recordsToUpdateExtId.add(newRec);
          }
      }
      if (!recordsToUpdateExtId.isEmpty()) {
        tcpl_NamingConventionUtil.setExtenralIdField(recordsToUpdateExtId,'Credit_Note__c');
      }
    }

    public override void handleAfterInsert(){
        String customerSAPNo = [Select Distributor__r.tcpl_customerSapNo__c from Credit_Note__c where id =:Trigger.new[0].id]?.Distributor__r.tcpl_customerSapNo__c;
        // tcpl_utilityforNamingConventionv2.firePlatformEvent((Map<id,Credit_Note__c>)trigger.newMap,'Credit_Note__c',customerSAPNo);
        tcpl_NamingConventionUtil.firePlatformEvent((Map<id, Credit_Note__c>) Trigger.newMap,'Credit_Note__c','Credit_Note_Name_Seq__e');     
    //added by Manoj to create b2b primary Credit Note for SMDMS Changes
       TCPL_SUBDUtility.createPrimaryCreditNote((Map<id,Credit_Note__c>)trigger.newMap);
    }
}