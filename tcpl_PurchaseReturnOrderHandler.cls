/**
* @description       : 
* @author            : ChangeMeIn@UserSettingsUnder.SFDoc
* @group             : 
* @last modified on  : 11-09-2023
* @last modified by  : Chandana
**/
public class tcpl_PurchaseReturnOrderHandler  extends tcpl_TriggerHandlerBase{
    public override void handleAfterInsert()
    {
        tcpl_PurchaseReturnOrderHelper.handleApprovalProcessSubmission((List<tcpl_purchaseReturnOrder__c>)trigger.new);
        //String customerSAPNo = [Select tcpl_distributor__r.tcpl_customerSapNo__c from tcpl_purchaseReturnOrder__c where id =:Trigger.new[0].id]?.tcpl_distributor__r.tcpl_customerSapNo__c;
        //tcpl_utilityforNamingConventionv2.firePlatformEvent((Map<id,tcpl_purchaseReturnOrder__c>)trigger.newMap,'tcpl_purchaseReturnOrder__c','');
        tcpl_NamingConventionUtil.firePlatformEvent((Map<id, tcpl_purchaseReturnOrder__c>) Trigger.newMap,'tcpl_purchaseReturnOrder__c','PurchaseReturnOrderNameSeq__e');
        //for sharing records
        //TCPL_SharingObjectRecordsHandler.sharePurchaseOrderSWithAccountTeams((Map<id,tcpl_purchaseReturnOrder__c>)trigger.newMap);
        // Catches SubDB returns created directly at 'SS Pickup Completed' (and CFA-completed returns) on insert. Added by Anuj Kumar on 09-09-2026
        tcpl_PurchaseReturnOrderHelper.updateTdsEligibilityOnInsert((List<tcpl_purchaseReturnOrder__c>)trigger.new);
    }
    public override void handleAfterUpdate()
    {
        //for Approval actions
       tcpl_PurchaseReturnOrderHelper.handleCFANotificationForCfaPickUpPending((List<tcpl_purchaseReturnOrder__c>)trigger.new);

      // tcpl_PurchaseReturnOrderHelper.handleApprovalProcessClosure((List<tcpl_purchaseReturnOrder__c>)trigger.new,(Map<id,tcpl_purchaseReturnOrder__c>)trigger.oldMap);
      // tcpl_PurchaseReturnOrderHelper.handleInventoryQuantityUpdate((List<tcpl_purchaseReturnOrder__c>)trigger.new,(Map<id,tcpl_purchaseReturnOrder__c>)trigger.oldMap);
      tcpl_PurchaseReturnOrderHelper.handleRejectedReturn((List<tcpl_purchaseReturnOrder__c>)Trigger.new,(Map<Id, tcpl_purchaseReturnOrder__c>)Trigger.oldMap);
      tcpl_PurchaseReturnOrderHelper.handleCFANotificationForCfaPickUpConfirm((List<tcpl_purchaseReturnOrder__c>)trigger.new,(Map<id,tcpl_purchaseReturnOrder__c>)trigger.oldMap);
      tcpl_PurchaseReturnOrderHelper.handlePurchaseOrderSyncToSAP((List<tcpl_purchaseReturnOrder__c>)trigger.new,(Map<id,tcpl_purchaseReturnOrder__c>)trigger.oldMap);
      tcpl_PurchaseReturnOrderHelper.updateTdsEligibility((List<tcpl_purchaseReturnOrder__c>)trigger.new,(Map<Id, tcpl_purchaseReturnOrder__c>)trigger.oldMap);// Added by Anuj Kumar on 09-09-2026
    }

    public override void handleBeforeUpdate()
    {
      //Added by Bopanna - 20-1-2026
      UtilityClass.setReasonForChangeValue(trigger.new, trigger.oldMap);

      List<tcpl_purchaseReturnOrder__c> recordsToUpdateExtId = new List<tcpl_purchaseReturnOrder__c>();
        for (Integer i = 0; i < Trigger.new.size(); i++) {
            tcpl_purchaseReturnOrder__c newRec = (tcpl_purchaseReturnOrder__c) Trigger.new[i];
            tcpl_purchaseReturnOrder__c oldRec = (tcpl_purchaseReturnOrder__c) Trigger.oldMap.get(newRec.Id);

            if (newRec.Name != oldRec.Name) {
                recordsToUpdateExtId.add(newRec);
            }
        }
        if (!recordsToUpdateExtId.isEmpty()) {
            tcpl_NamingConventionUtil.setExtenralIdField(recordsToUpdateExtId,'tcpl_purchaseReturnOrder__c');
        }
    }

    public override void handleBeforeInsert(){
        //Added by Bopanna - 20-1-2026
        UtilityClass.setReasonForChangeValue(trigger.new, null);
        //tcpl_PurchaseReturnOrderHelper.getNamingConvention((List<tcpl_purchaseReturnOrder__c>)trigger.new);
    }
    
}