/**
 * @description       : 
 * @author            : raghu
 * @group             : 
 * @last modified on  : 07-28-2025
 * @last modified by  : raghu
**/
public class tcpl_UpdateObjNameSeqBatch implements Database.Batchable<Sobject>,schedulable,Database.stateful{
    set<ID> setOfAccountIds = new set<ID>();
    Integer endTimeInMin = -2;
    Integer batchSize = 1;
    Datetime endTime = Datetime.now().addMinutes(endTimeInMin);//end time to consider in the soql

    public tcpl_UpdateObjNameSeqBatch() {

    }

    // excecute method for the schedulable interface
    public void execute(SchedulableContext SC) {
        //Every time the batch class will get executed from this schedulable context when it's scheduled
        tcpl_UpdateObjNameSeqBatch shn = new tcpl_UpdateObjNameSeqBatch(); 
        database.executeBatch(shn,1);
    }

    public Database.QueryLocator start(Database.BatchableContext bc){ 
        return Database.getQuerylocator([select id,tcpl_customerSapNo__c from Account limit 1]); //1
    }

    public void execute(Database.BatchableContext bc, List<Account> listAccount){

        // Credit Note object
        Map<Id, Credit_Note__c> creditNoteMap = new Map<Id, Credit_Note__c>([select Id,Distributor__c from Credit_Note__c where name like 'a01%'
                                    AND CreatedDate = LAST_N_DAYS:5 AND CreatedDate <= :endTime limit  500]);

        if(!creditNoteMap.isEmpty()){
            tcpl_NamingConventionUtil.firePlatformEvent(creditNoteMap,'Credit_Note__c','Credit_Note_Name_Seq__e');                            
        }

        // secondary Return Object
        map<Id,tcpl_Secondary_Returns__c> mapSecondaryRetrn = new map<Id,tcpl_Secondary_Returns__c>([select Id,tcpl_Distributor__c from tcpl_Secondary_Returns__c where name like 'a0l%'
                                    AND CreatedDate = LAST_N_DAYS:5 AND CreatedDate <= :endTime limit  500 ]);

        if(!mapSecondaryRetrn.isEmpty()){
            tcpl_NamingConventionUtil.firePlatformEvent(mapSecondaryRetrn,'tcpl_Secondary_Returns__c','SecondaryReturnsNameSeq__e'); 
        }

        // secondary Delivery object
        Map<Id,tcpl_secondaryDelivery__c> mapSecondaryDelivery = new Map<Id,tcpl_secondaryDelivery__c>([select Id,DB_SS_Sub_DB__c from tcpl_secondaryDelivery__c  where name like 'a1L%' AND
                                                CreatedDate = LAST_N_DAYS:5 AND CreatedDate <=:endTime limit  500]);

        if(!mapSecondaryDelivery.isEmpty()){
            tcpl_NamingConventionUtil.firePlatformEvent(mapSecondaryDelivery,'tcpl_secondaryDelivery__c','secondaryDeliveryNameSeq__e');
        }

        //purchase Return object
        map<id,tcpl_purchaseReturnOrder__c> mapPurchaseReturn = new map<id,tcpl_purchaseReturnOrder__c>([select Id,tcpl_distributor__c from tcpl_purchaseReturnOrder__c where name like 'a1H%'
                                            AND CreatedDate = LAST_N_DAYS:5 AND CreatedDate <= :endTime  limit 500]);

        if(!mapPurchaseReturn.isEmpty()){
            tcpl_NamingConventionUtil.firePlatformEvent(mapPurchaseReturn,'tcpl_purchaseReturnOrder__c','PurchaseReturnOrderNameSeq__e');
        }
    }

    public void finish(Database.BatchableContext bc){
        
    }
}