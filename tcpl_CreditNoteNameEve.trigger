/**
 * @description       : 
 * @author            : raghu
 * @group             : 
 * @last modified on  : 07-01-2025
 * @last modified by  : raghu
**/
trigger tcpl_CreditNoteNameEve on Credit_Note_Name_Seq__e (after insert) {

    List<tcpl_NamingConventionUtil.RecordsToUpdateNameWrap> orderEventWrapList = new List<tcpl_NamingConventionUtil.RecordsToUpdateNameWrap>();

    for(Credit_Note_Name_Seq__e pE : Trigger.new){
        if(pE.tcpl_AccountSFId__c != null){
            tcpl_NamingConventionUtil.RecordsToUpdateNameWrap orderEventWrap = new tcpl_NamingConventionUtil.RecordsToUpdateNameWrap();
            orderEventWrap.AccountSfId = pE.tcpl_AccountSFId__c;
            orderEventWrap.objectName = pE.tcpl_objectName__c;
            orderEventWrap.recordId = pE.tcpl_recordId__c;
            orderEventWrapList.add(orderEventWrap);
        }
    }
    if(orderEventWrapList.size() > 0){
        tcpl_NamingConventionUtil.handlePlatformEvent(orderEventWrapList);
    }
}