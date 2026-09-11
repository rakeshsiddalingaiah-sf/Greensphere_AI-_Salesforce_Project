/**
 * @description       : 
 * @author            : raghu
 * @group             : 
 * @last modified on  : 07-21-2025
 * @last modified by  : raghu
**/
public with sharing class tcpl_NamingConventionUtil {
    /**this methods handles the subscribed Platform event */
    public static void handlePlatformEvent(List<RecordsToUpdateNameWrap> newRequests) {
        // List < PopulateNameSeq__e > newRequests = newRequestsC.deepClone();
        try{
        if(newRequests.isEmpty()) return;

        // String objectName = newRequests[0].tcpl_objectName__c;
        Set<Id> recIds = new set<Id>();
        set<id> accIds = new set<Id>();
        Map<Id,set<Id>> accIdvsRecIds = new Map<Id,set<Id>>();
        Map<Id, Map<String, Set<Id>>> accountToObjectToRecordIds = new Map<Id, Map<String, Set<Id>>>();
        String selectedAccountId = '';
        String firstObjectName;
        // String toFilterObjectIdSeries = 'a1M';


        // this constructs AcciD VS map<ObjectName,set<recordId>>
        for(RecordsToUpdateNameWrap req : newRequests){
            if(req.recordId != null && req.objectName != null && req.AccountSfId != null){
                String accId = req.AccountSfId;
                String objectName = req.objectName;
                String recId = req.recordId;

                if (!accountToObjectToRecordIds.containsKey(accId)) {
                    accountToObjectToRecordIds.put(accId, new Map<String, Set<Id>>());
                }
                Map<String, Set<Id>> objectToIds = accountToObjectToRecordIds.get(accId);
                if (!objectToIds.containsKey(objectName)) {
                    objectToIds.put(objectName, new Set<Id>());
                }

                objectToIds.get(objectName).add(recId);
                accIds.add(accId); //for logging only remove after testing
            }
        }

        /**corner case where partitioning not working more than 1 acc came then filter and process 1 acc at a time */
        Map<String, Set<Id>> objectToRecordIdsForOneAccount;
        List<SObject> platformEvents = new List<SObject>();
        // Schema.SObjectType eventType = tcpl_UtilityNamingConventionConstant.knownObjectTypes.get('PopulateNameSeq__e');
        // Schema.SObjectType eventType = Schema.getGlobalDescribe().get('PopulateNameSeq__e');
        if (!accountToObjectToRecordIds.isEmpty()) {
            Boolean isFirst = true;
            for (Id accId : accountToObjectToRecordIds.keySet()) {
                Map<String, Set<Id>> objectToRecordIds = accountToObjectToRecordIds.get(accId);
                if(isFirst){
                    selectedAccountId = accId;
                    objectToRecordIdsForOneAccount = objectToRecordIds;
                    if (!objectToRecordIdsForOneAccount.isEmpty()) {
                        firstObjectName = objectToRecordIdsForOneAccount.keySet().iterator().next();
                    }
                    isFirst = false; // mark first account as handled
                }
                else {
                    // Remaining accounts: fire one platform event per account
                    for (String objectName : objectToRecordIds.keySet()) {
                        Set<Id> recordIdList = objectToRecordIds.get(objectName);

                        if (!recordIdList.isEmpty()) {
                            Id recordId = recordIdList.iterator().next();
                            //Schema.SObjectType eventType = tcpl_UtilityNamingConventionConstant.knownObjectTypes.get(objectName);
                            String eventApiName;
                            
                            if(objectName == 'Credit_Note__c'){
                                eventApiName = 'Credit_Note_Name_Seq__e';
                            }
                            else if(objectName == 'tcpl_Secondary_Returns__c'){
                                eventApiName = 'SecondaryReturnsNameSeq__e';
                            }
                            else if(objectName == 'tcpl_purchaseReturnOrder__c'){
                                eventApiName = 'PurchaseReturnOrderNameSeq__e';
                            }
                            else if(objectName == 'tcpl_secondaryDelivery__c'){
                                eventApiName = 'secondaryDeliveryNameSeq__e';
                            }
                            else{
                                eventApiName = 'PopulateNameSeq__e';
                            }
                            
                            Schema.SObjectType eventType =
                                tcpl_UtilityNamingConventionConstant.knownObjectTypes.get(eventApiName);
                            
                            if(eventType == null){
                                continue;
                            }
                            
                           
                            SObject eventRecord = eventType.newSObject();
                            eventRecord.put('tcpl_AccountSFId__c', accId);
                            eventRecord.put('tcpl_objectName__c', objectName);
                            eventRecord.put('tcpl_recordId__c', recordId);

                            platformEvents.add(eventRecord);

                            break; // Only one event per account
                        }
                    }
                }
            }
        }

        // Set<Id> recIdss = objectToRecordIdsForOneAccount.get(firstObjectName);
        // tcpl_logger__c logger = new tcpl_logger__c();
        // logger.Class_Name__c = 'tcpl_NamingConventionUtil';
        // logger.Method_Name__c = 'handlePlatformEvent'+firstObjectName;
        // logger.Request_Body__c = JSON.serialize(newRequests);
        // logger.tcpl_Verbose__c = 'invId '+ String.valueOf(recIdss.Size());
        // logger.tcpl_Verbose2__c = 'accId '+String.valueOf(accIds.Size());
        // insert logger;
        Boolean enableLockMechanismForInvoiceName = System.Label.EnableLockMechanismForInvoiceName.equalsIgnoreCase('True');
        
        Boolean processInvoiceNaming;
        if(!enableLockMechanismForInvoiceName){
            processInvoiceNaming = false;
        } else{
            processInvoiceNaming = lockOrUnlockRecords(selectedAccountId, false);
        }

        if(!processInvoiceNaming){
            Datetime endTime = Datetime.now().addSeconds(-2);//Datetime.now().addMinutes(-5);
            String accFieldName = formatQueryWithAccountField(firstObjectName,'{0}');
            String toFilterObjectId = getObjectPrefix(firstObjectName);
            //  String queryRecWithIdName = 'select id from '+firstObjectName +' Where '+accFieldName+ '=:selectedAccountId and NAME LIKE \''+toFilterObjectId+'%\' and CreatedDate = LAST_N_DAYS:15 AND CreatedDate <= :endTime limit 500';
            String queryRecWithIdName = 'select id from '+firstObjectName +' Where '+accFieldName+ '=:selectedAccountId and NAME LIKE \''+toFilterObjectId+'%\' and CreatedDate = LAST_N_DAYS:15 AND LastModifiedDate <= :endTime ';
            queryRecWithIdName += firstObjectName == tcpl_UtilityNamingConventionConstant.SECONDARY_SALES_INVOICE ? ' and tcpl_botreeInvoiceNo__c  = null limit 500' : ' limit 500';
            List<SObject> queryRecWithIdNameList = Database.query(queryRecWithIdName);
            set<Id> recordIdsSet = new set<Id>();
            if(queryRecWithIdNameList.size() > 0){
                Map<String, Set<Id>> objectToRecordIds = accountToObjectToRecordIds.get(selectedAccountId);

                // Ensure object name entry exists
                if (!objectToRecordIds.containsKey(firstObjectName)) {
                    objectToRecordIds.put(firstObjectName, new Set<Id>());
                }
                Set<Id> recordIds = objectToRecordIds.get(firstObjectName);
                for(Sobject obj : queryRecWithIdNameList){
                    if (!recordIds.contains(obj.Id)) {
                        RecordsToUpdateNameWrap rec = new RecordsToUpdateNameWrap();
                        rec.AccountSfId = selectedAccountId;
                        rec.recordId = obj.Id;
                        rec.objectName = firstObjectName;
                        newRequests.add(rec);
                        recordIds.add(obj.Id);
                    }
                    
                }
                recordIdsSet = recordIds;
            }
            
            String customerSapNo = [select id,tcpl_customerSapNo__c from account where Id=:selectedAccountId].tcpl_customerSapNo__c;
            map<String,String> invRcrdTypeNameVsIdMap = new map<String,String>();
            if(objectToRecordIdsForOneAccount.containsKey(tcpl_UtilityNamingConventionConstant.SECONDARY_SALES_INVOICE)){
                set<Id> invIds = objectToRecordIdsForOneAccount.get(tcpl_UtilityNamingConventionConstant.SECONDARY_SALES_INVOICE);

                for (tcpl_secondarySalesInvoice__c inv : [select Id,RecordType.Name,RecordTypeId from tcpl_secondarySalesInvoice__c where Id IN: invIds
                                                        and recordTypeId !=: tcpl_SalesSecondaryInvoiceConstants.SECONDARY_INVOICE_RECORDTYPE_IDT_STOCK_TRANSFER]) {
                    invRcrdTypeNameVsIdMap.put(inv.Id,inv.RecordType.Name);
                }
            }

            List<Naming_Sequence__c> namingSeqList = [select id,tcpl_Prefix__c,tcpl_objectName__c,tcpl_Type__c,tcpl_Unique_Sequence__c,tcpl_DefaultSequence__c,tcpl_finalPrefix__c from Naming_Sequence__c
                                                where tcpl_objectName__c =: objectToRecordIdsForOneAccount.keySet() and tcpl_Status__c =: tcpl_UtilityNamingConventionConstant.ACTIVE and tcpl_distributor__c =:selectedAccountId];

            Boolean isMultipleNmaingSeq = false;
            String lastTwoDigit = getLastTwoDigitForYear();
            // String accId = newRequests[0].tcpl_AccountSFId__c;

            Map <String, String> defaultGetNamingPatterns = new Map <String, String>(); 
            Map<String,Map<String,NamingSequenceWrapper>> objectVsNamesequenceMap = new Map <String,Map<String,NamingSequenceWrapper>>();
            // set<string> objectsWithoutNamingSeq = new set<string>();
            Set<String> ojbectsWithNamingSeq = new Set<String>();
            for(Naming_Sequence__c namingSeq : [select id,tcpl_Prefix__c,tcpl_objectName__c,tcpl_Type__c,tcpl_Unique_Sequence__c,tcpl_DefaultSequence__c,tcpl_finalPrefix__c from Naming_Sequence__c
                                                where tcpl_objectName__c =: objectToRecordIdsForOneAccount.keySet() and tcpl_Status__c =: tcpl_UtilityNamingConventionConstant.ACTIVE and tcpl_distributor__c =:selectedAccountId]){

                if(namingSeq.tcpl_objectName__c == tcpl_UtilityNamingConventionConstant.SECONDARY_SALES_INVOICE && namingSeq.tcpl_DefaultSequence__c == false){
                    isMultipleNmaingSeq = true;
                    String objectName = namingSeq.tcpl_objectName__c;
                    if(!objectVsNamesequenceMap.containsKey(objectName)){
                        objectVsNamesequenceMap.put(objectName, new map<String,NamingSequenceWrapper>());
                    }
                    System.debug('objectVsNamesequenceMap>>'+objectVsNamesequenceMap);
                    switch on namingSeq.tcpl_Type__c {
                        when 'Tax Invoice' {
                            addObjectVsNameSeqMap(objectVsNamesequenceMap, namingSeq.tcpl_ObjectName__c, namingSeq.tcpl_Type__c, namingSeq.tcpl_Unique_Sequence__c, namingSeq.tcpl_finalPrefix__c);
                        }
                        when 'Bill of supply' {
                            addObjectVsNameSeqMap(objectVsNamesequenceMap, namingSeq.tcpl_ObjectName__c, namingSeq.tcpl_Type__c, namingSeq.tcpl_Unique_Sequence__c, namingSeq.tcpl_finalPrefix__c);
                        }
                        when 'Non GST Invoice' {
                            addObjectVsNameSeqMap(objectVsNamesequenceMap, namingSeq.tcpl_ObjectName__c, namingSeq.tcpl_Type__c, namingSeq.tcpl_Unique_Sequence__c, namingSeq.tcpl_finalPrefix__c);
                        }
                    }
                } else {
                    String objectName = namingSeq.tcpl_objectName__c;
                    if(!objectVsNamesequenceMap.containsKey(objectName)){
                        objectVsNamesequenceMap.put(objectName, new map<String,NamingSequenceWrapper>());
                    }
                    addObjectVsNameSeqMap(objectVsNamesequenceMap, namingSeq.tcpl_ObjectName__c, tcpl_UtilityNamingConventionConstant.DEFAULT_KEY, namingSeq.tcpl_Unique_Sequence__c, namingSeq.tcpl_finalPrefix__c);
                }
                ojbectsWithNamingSeq.add(namingSeq.tcpl_objectName__c);
            }

            Set<String> objectsWithoutNamingSeq = new Set<String>(objectToRecordIdsForOneAccount.keySet());
            objectsWithoutNamingSeq.removeAll(ojbectsWithNamingSeq);
        
            if(objectVsNamesequenceMap.isEmpty() || objectVsNamesequenceMap == null || !objectsWithoutNamingSeq.isEmpty()){
                defaultGetNamingPatterns = getNamingPatterns(); //if naming sequence Not defined for the DB then take the default pattern
                List<Naming_Sequence__c> listOfNamingSqToInsert = new List<Naming_Sequence__c>();
                for(string objName : objectToRecordIdsForOneAccount.keySet()){
                    string objSeqPrefix, objSeq;
                    if(defaultGetNamingPatterns.containsKey(objName)){
                        String pattern = defaultGetNamingPatterns.get(objName);
                        objSeqPrefix = pattern.replace('{DB}', customerSapNo).replace('{YR}', lastTwoDigit).replace('{SEQ}', ''); //if naming esqunce not defined construct one to get th exisintg 
                        objSeq = objSeqPrefix + '000001';
                    }

                    if(!objectVsNamesequenceMap.containsKey(objName)){
                        objectVsNamesequenceMap.put(objName, new map<String,NamingSequenceWrapper>());
                    }
                    /**if there's only for few objects default naimng sequence not defiend then only for those default sequence willbe created else for all */
                    if(!objectsWithoutNamingSeq.isEmpty() ){ //&& objectsWithoutNamingSeq.containsKey(objName)
                        addObjectVsNameSeqMap(objectVsNamesequenceMap, objName, tcpl_UtilityNamingConventionConstant.DEFAULT_KEY, objSeq, objSeqPrefix);
                        listOfNamingSqToInsert.add(createDefaultNamingSeqForDb(objName,objSeqPrefix.substring(0, 2),selectedAccountId,objSeq,objSeqPrefix));
                    } else{
                        addObjectVsNameSeqMap(objectVsNamesequenceMap, objName, tcpl_UtilityNamingConventionConstant.DEFAULT_KEY, objSeq, objSeqPrefix);
                        listOfNamingSqToInsert.add(createDefaultNamingSeqForDb(objName,objSeqPrefix.substring(0, 2),selectedAccountId,objSeq,objSeqPrefix));
                    }
                }
                if(!listOfNamingSqToInsert.isEmpty()){
                    insert listOfNamingSqToInsert;
                }
            }

            
            for(string objName : objectToRecordIdsForOneAccount.keySet()){
                
                if(objectVsNamesequenceMap.containsKey(objName)){
                    map<String,NamingSequenceWrapper> typeVsNamingSeq = objectVsNamesequenceMap.get(objName);
                    if(objName == tcpl_UtilityNamingConventionConstant.SECONDARY_SALES_INVOICE && objectVsNamesequenceMap.get(objName).size() == 3){
                        
                        String toFilterAseries, taxInvExistingSeq, billOfSupplyExisitngSeq,nonGstExistingSeq,defaultPrefix;
                        if(typeVsNamingSeq.containsKey(tcpl_UtilityNamingConventionConstant.TAX_INVOICE)){
                            String soql = 'select id,Name,tcpl_Name_Prefix__c,RecordTypeId from '+ objName+ ' Where {0}=:selectedAccountId '; 
                            soql = formatQueryWithAccountField(objName, soql);
                            String toFilterObjectIdSeries = getObjectPrefix(objName);
                            defaultPrefix = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.TAX_INVOICE).objPrefix;
                            toFilterAseries = defaultPrefix + 'A';
                            soql += ' and tcpl_Name_Prefix__c=:defaultPrefix  and (NOT NAME LIKE \''+toFilterObjectIdSeries+'%\') and (NOT Name LIKE \''+toFilterAseries+'%\') and tcpl_botreeInvoiceNo__c  = null order by Name desc limit 1';
                            List<SObject> sObjectList = Database.query(soql);
                            if(sObjectList.size() > 0){
                                typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.TAX_INVOICE).objExistingSeq  = sObjectList[0].get('Name').toString();
                            }
                        }

                        if(typeVsNamingSeq.containsKey(tcpl_UtilityNamingConventionConstant.BILL_OF_SUPPLY)){
                            String soql = 'select id,Name,tcpl_Name_Prefix__c,RecordTypeId from '+ objName+ ' Where {0}=:selectedAccountId '; 
                            soql = formatQueryWithAccountField(objName, soql);
                            String toFilterObjectIdSeries = getObjectPrefix(objName);
                            defaultPrefix = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.BILL_OF_SUPPLY).objPrefix;
                            toFilterAseries =  defaultPrefix + 'A';
                            soql += ' and tcpl_Name_Prefix__c=:defaultPrefix  and (NOT NAME LIKE \''+toFilterObjectIdSeries+'%\') and (NOT Name LIKE \''+toFilterAseries+'%\') and tcpl_botreeInvoiceNo__c  = null order by Name desc limit 1';
                            System.debug('soql>>'+soql);
                            List<SObject> sObjectList = Database.query(soql);
                            if(sObjectList.size() > 0){
                                typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.BILL_OF_SUPPLY).objExistingSeq  = sObjectList[0].get('Name').toString();
                            }
                        }

                        if(typeVsNamingSeq.containsKey(tcpl_UtilityNamingConventionConstant.NON_GST_INVOICE)){
                            String soql = 'select id,Name,tcpl_Name_Prefix__c,RecordTypeId from '+ objName+ ' Where {0}=:selectedAccountId '; 
                            soql = formatQueryWithAccountField(objName, soql);
                            String toFilterObjectIdSeries = getObjectPrefix(objName);
                            defaultPrefix = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.NON_GST_INVOICE).objPrefix;
                            toFilterAseries = defaultPrefix + 'A';
                            soql += ' and tcpl_Name_Prefix__c=:defaultPrefix  and (NOT NAME LIKE \''+toFilterObjectIdSeries+'%\') and (NOT Name LIKE \''+toFilterAseries+'%\') and tcpl_botreeInvoiceNo__c  = null order by Name desc limit 1';
                            List<SObject> sObjectList = Database.query(soql);
                            if(sObjectList.size() > 0){
                                typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.NON_GST_INVOICE).objExistingSeq  = sObjectList[0].get('Name').toString();
                            }
                        }
                    } else{
                        String toFilterAseries;
                        String soql = 'select id,Name,tcpl_Name_Prefix__c from '+ objName+ ' Where {0}=:selectedAccountId ';  //RecordTypeId
                        soql = formatQueryWithAccountField(objName, soql);
                        String toFilterObjectIdSeries = getObjectPrefix(objName);
                        toFilterAseries = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.DEFAULT_KEY).objPrefix + 'A';
                        String defaultName = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.DEFAULT_KEY).objPrefix;
                        soql += ' and Name LIKE \''+defaultName+'%\' and (NOT NAME LIKE \''+toFilterObjectIdSeries+'%\') and (NOT Name LIKE \''+toFilterAseries+'%\')  ';
                        soql += firstObjectName == tcpl_UtilityNamingConventionConstant.SECONDARY_SALES_INVOICE ? ' and tcpl_botreeInvoiceNo__c  = null order by Name desc limit 1' : ' order by Name desc limit 1';
                        List<SObject> sObjectList = Database.query(soql);
                        if(sObjectList.size() > 0){
                            typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.DEFAULT_KEY).objExistingSeq  = sObjectList[0].get('Name').toString();
                        }
                    }
                }
            }

            List<SObject> recordsToUpdate = new List<SObject>();
            //looping platform events records here
            for(RecordsToUpdateNameWrap req: newRequests){
                // to process set of recIds for one accID if Platform event partitioning by accId bypassed for some unforseen reason to handle it this approach
                if(req.AccountSfId == selectedAccountId){ 
                    map<String,NamingSequenceWrapper> typeVsNamingSeq = objectVsNamesequenceMap.get(req.objectName);
                    Schema.SObjectType sobType = tcpl_UtilityNamingConventionConstant.knownObjectTypes.get(req.objectName);
                    // Schema.SObjectType sobType = Schema.getGlobalDescribe().get(req.objectName);
                    Sobject sob = sobType.newSObject();
                    sob.put('ID', req.recordId);
                    //sob.put('Is_Name_Populated_by_PE__c', true); 
                    // String existingSeq, defaltSeq, prefix;
                    if(req.objectName == tcpl_UtilityNamingConventionConstant.SECONDARY_SALES_INVOICE && objectVsNamesequenceMap.get(req.objectName).size() == 3){
                        if(invRcrdTypeNameVsIdMap.containsKey(req.recordId) && invRcrdTypeNameVsIdMap.get(req.recordId) == tcpl_UtilityNamingConventionConstant.TAX_INVOICE){
                            String taxInvExistingSeq = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.TAX_INVOICE).objExistingSeq;
                            String taxInvseq = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.TAX_INVOICE).objDefaultSeq;
                            System.debug('taxInvExistingSeq>>'+taxInvExistingSeq);
                            System.debug('taxInvseq>>'+taxInvseq);
                            Integer next = taxInvExistingSeq != '' ? Integer.valueOf(taxInvExistingSeq.right(6)) + 1: Integer.valueOf(taxInvseq.right(6));
                            String newName = taxInvseq.left(taxInvseq.length() - 6) + ('000000' + next).right(6);
                            sob.put('Name', newName);  
                            sob.put('tcpl_Name_Prefix__c', typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.TAX_INVOICE).objPrefix); 
                            typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.TAX_INVOICE).objDefaultSeq = getNextName(taxInvseq);
                            if(taxInvExistingSeq != ''){
                                typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.TAX_INVOICE).objExistingSeq = getNextName(taxInvExistingSeq);
                            }
                        }
                        if(invRcrdTypeNameVsIdMap.containsKey(req.recordId) && invRcrdTypeNameVsIdMap.get(req.recordId) == tcpl_UtilityNamingConventionConstant.NON_GST_INVOICE){
                            String nonGstExistingSeq = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.NON_GST_INVOICE).objExistingSeq;
                            String nonGstseq = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.NON_GST_INVOICE).objDefaultSeq;
                            Integer next = nonGstExistingSeq != '' ? Integer.valueOf(nonGstExistingSeq.right(6)) + 1: Integer.valueOf(nonGstseq.right(6));
                            String newName = nonGstseq.left(nonGstseq.length() - 6) + ('000000' + next).right(6);
                            sob.put('Name', newName);  
                            sob.put('tcpl_Name_Prefix__c', typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.NON_GST_INVOICE).objPrefix); 
                            typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.NON_GST_INVOICE).objDefaultSeq = getNextName(nonGstseq);
                            if(nonGstExistingSeq != ''){
                                typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.NON_GST_INVOICE).objExistingSeq = getNextName(nonGstExistingSeq);
                            }
                        }
                        if(invRcrdTypeNameVsIdMap.containsKey(req.recordId) && invRcrdTypeNameVsIdMap.get(req.recordId) == tcpl_UtilityNamingConventionConstant.BILL_OF_SUPPLY){
                            String billOfSupplyExistingSeq = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.BILL_OF_SUPPLY).objExistingSeq;
                            String billOfSupplyseq = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.BILL_OF_SUPPLY).objDefaultSeq;
                            Integer next = billOfSupplyExistingSeq != '' ? Integer.valueOf(billOfSupplyExistingSeq.right(6)) + 1: Integer.valueOf(billOfSupplyseq.right(6));
                            String newName = billOfSupplyseq.left(billOfSupplyseq.length() - 6) + ('000000' + next).right(6);
                            sob.put('Name', newName);  
                            sob.put('tcpl_Name_Prefix__c', typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.BILL_OF_SUPPLY).objPrefix); 
                            typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.BILL_OF_SUPPLY).objDefaultSeq = getNextName(billOfSupplyseq);
                            System.debug('billOfSupplyExistingSeq>>'+billOfSupplyExistingSeq);
                            if(billOfSupplyExistingSeq !=''){
                                typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.BILL_OF_SUPPLY).objExistingSeq = getNextName(billOfSupplyExistingSeq);
                            }
                        }
                    } else {
                        String existingSeq = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.DEFAULT_KEY).objExistingSeq;
                        String objSeq = typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.DEFAULT_KEY).objDefaultSeq;
                        system.debug('objSeq>>'+objSeq);
                        system.debug('existingSeq>>'+existingSeq);
                        Integer next = existingSeq != '' ? Integer.valueOf(existingSeq.right(6)) + 1: Integer.valueOf(objSeq.right(6));
                        String newName = objSeq.left(objSeq.length() - 6) + ('000000' + next).right(6);
                        sob.put('Name', newName);  
                        sob.put('tcpl_Name_Prefix__c', typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.DEFAULT_KEY).objPrefix); 
                        typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.DEFAULT_KEY).objDefaultSeq = getNextName(objSeq);
                        if(existingSeq != ''){
                            typeVsNamingSeq.get(tcpl_UtilityNamingConventionConstant.DEFAULT_KEY).objExistingSeq = getNextName(existingSeq);
                        }
                    }
                    recordsToUpdate.add(sob);
                }           
            }
            system.debug('recordsToUpdate>>'+recordsToUpdate);
            List<tcpl_logger__c> loggerListInsert = new List<tcpl_logger__c>();
            if(recordsToUpdate.size() > 0){
                String recQuery = 'select id,Name from '+firstObjectName +' Where id IN:recordIdsSet ';
                List<SObject> queryRecIdName = Database.query(recQuery);
                Boolean containsNonSalesforceId = false;
                Boolean checkIfNameNotId = System.Label.EnableNamingSeqCheck.equalsIgnoreCase('True');
                for(SObject rec : queryRecIdName){
                    if(checkIfNameNotId){
                        String nameVal = String.valueOf(rec.get('Name'));

                        // Always extract last 6 chars safely
                        // String last6 = nameVal.right(6); // Safe even if string is < 6 characters

                        // // If last 6 are only digits → not a Salesforce ID
                        // if (Pattern.matches('^[0-9]{6}$', last6)) {
                        //     containsNonSalesforceId = true;
                        //     break;
                        // }

                        if(String.valueOf(rec.Id).substring(0, 15) != nameVal){
                            containsNonSalesforceId = true;
                            break;
                        }
                    }
                }
                if (!containsNonSalesforceId) {
                    List < Database.SaveResult > results = Database.update(recordsToUpdate, false);
                    for (Database.SaveResult sr: results) {
                        if (sr.isSuccess()) {
                            
                        } else {
                            for (Database.Error err: sr.getErrors()) {
                                tcpl_logger__c log = tcpl_loggerUtility.returnLog('Exception', 'tcpl_utilityForNamingConvntionV3', 'handlePlatformEvent', err.getMessage(), '', JSON.serialize(recordsToUpdate), JSON.serialize('Error With objectName naming'));
                                if (log != null) {
                                    // Insert log;
                                    loggerListInsert.add(log);
                                }
                            }
                        }
                    }
                }
            }
            if(!loggerListInsert.isEmpty()){
                insert loggerListInsert;
            }

            if (!platformEvents.isEmpty()) {
                EventBus.publish(platformEvents);
            }
            if(enableLockMechanismForInvoiceName){
            //unlock the child record, after each order is processed for the DB
            processInvoiceNaming = lockOrUnlockRecords(selectedAccountId, true);
            }
        }
    }
    /*catch(Exception e){
        tcpl_logger__c loggerss = new tcpl_logger__c();
        loggerss.Class_Name__c = 'handlePLatformFailed';
        loggerss.Method_Name__c = 'handlePlatformEvent';
        loggerss.Request_Body__c = e.getMessage();
        insert loggerss;
    }*/
        catch (Exception e) {
            
            System.debug('Exception Type : ' + e.getTypeName());
            System.debug('Message        : ' + e.getMessage());
            System.debug('Line Number    : ' + e.getLineNumber());
            System.debug('Stack Trace    : ' + e.getStackTraceString());
            
            tcpl_logger__c logEvent = tcpl_loggerUtility.returnLog(
                'Exception',
                'tcpl_NamingConventionUtil',
                'handlePlatformEvent',
                e.getMessage()
                + ' | Line: ' + e.getLineNumber()
                + ' | Type: ' + e.getTypeName(),
                e.getStackTraceString(),
                JSON.serialize(newRequests),
                null
            );
            
            if(logEvent != null){
                insert logEvent;
            }
            
            throw e; // Optional but recommended while debugging
        }
    }

    public static Map < String, String > getNamingPatterns() {
        Map < String, String > patterns = new Map < String, String > ();
        for (tcpl_namingConvention__mdt patternData: [SELECT ObjectApiName__c, tcpl_Pattern__c FROM tcpl_namingConvention__mdt ]) { //WHERE ObjectApiName__c =: objectNames
            patterns.put(patternData.ObjectApiName__c, patternData.tcpl_Pattern__c);
        }
        return patterns;
    }
    
    public static String getLastTwoDigitForYear() {
        String currentFiscalYear = [SELECT FiscalYearSettings.Name FROM Period WHERE Type = 'Year'
            AND StartDate <= TODAY AND EndDate >= TODAY
        ].FiscalYearSettings.Name;
        String lastTwoDigitsYear = currentFiscalYear.substring(Math.max(0, currentFiscalYear.length() - 2));
        Decimal fiscalYearplusone = Decimal.valueOf(lastTwoDigitsYear) + 1;
        return String.valueOf(fiscalYearplusone);
    }

    public static String getNextName(String currentSeq) {
        Integer next = Integer.valueOf(currentSeq.right(6)) + 1;
        return currentSeq.left(currentSeq.length() - 6) + ('000000' + next).right(6);
    }

    public static String formatQueryWithAccountField(String objectApiName, String soql) {
        switch on objectApiName {
            when 'tcpl_GRN__c' {
                soql = String.format(soql, new List < Object > {
                    'tcpl_Customer_Name__c'
                });
            }
            when 'tcpl_Purchase_Invoice__c' {
                soql = String.format(soql, new List < Object > {
                    'tcpl_account__c'
                });
            }
            when 'Credit_Note__c' {
                soql = String.format(soql, new List < Object > {
                    'Distributor__c'
                });
            }
            when 'tcpl_purchaseReturnOrder__c' {
                soql = String.format(soql, new List < Object > {
                    'tcpl_distributor__c'
                });
            }
            when 'tcpl_secondaryDelivery__c' {
                soql = String.format(soql, new List < Object > {
                    'DB_SS_Sub_DB__c'
                });
            }
            when 'tcpl_secondarySalesOrder__c' {
                soql = String.format(soql, new List < Object > {
                    'Account__c'
                });
            }
            when 'tcpl_secondarySalesInvoice__c' {
                soql = String.format(soql, new List < Object > {
                    'tcpl_Account__c'
                });
            }
            when 'tcpl_Secondary_Returns__c' {
                soql = String.format(soql, new List < Object > {
                    'tcpl_Distributor__c'
                });
            }
        }
        /*if(objectApiName == 'tcpl_secondarySalesInvoice__c'){
             soql = soql + ' and tcpl_botreeInvoiceNo__c  = null ';
         }*/
        
        return soql;
    }

    /**to create default seq for a DB if not present */
    public static Naming_Sequence__c createDefaultNamingSeqForDb(String objectName,String defaultPrefix,String selectedAccountId,String objSeq,String finalPrefix ){
         Naming_Sequence__c defaultSeqForDB = new Naming_Sequence__c();
        try{
            // Naming_Sequence__c defaultSeqForDB = new Naming_Sequence__c();
            defaultSeqForDB.tcpl_objectName__c = objectName;
            defaultSeqForDB.tcpl_Prefix__c = defaultPrefix;
            defaultSeqForDB.tcpl_distributor__c = selectedAccountId;
            defaultSeqForDB.tcpl_FinYearPrefix__c = true;
            defaultSeqForDB.tcpl_DbCodePrefix__c = true;
            defaultSeqForDB.tcpl_DefaultSequence__c = true;
            defaultSeqForDB.tcpl_Status__c = 'Active';
            defaultSeqForDB.tcpl_Unique_Sequence__c = objSeq;
            defaultSeqForDB.tcpl_InitialCounterStartsFrom__c = '000001';
            defaultSeqForDB.tcpl_finalPrefix__c = finalPrefix; //.substring(0, objSeqPrefix.length() - 1);
            defaultSeqForDB.tcpl_Type__c = objectName == tcpl_UtilityNamingConventionConstant.SECONDARY_SALES_INVOICE ? ''  :tcpl_UtilityNamingConventionConstant.fieldLabelMapForDefaultType.get(objectName);
           
        } catch(exception ex){
            System.debug('exception occured creatingSeq rec:>>+ '+ex);
        }
        return defaultSeqForDB;
    }

    public static void addObjectVsNameSeqMap( Map<String, Map<String, NamingSequenceWrapper>> mapRef, String objectName,
                                        String type,String defaultSeq, String prefix)
    {
        NamingSequenceWrapper wrap = new NamingSequenceWrapper();
        wrap.objDefaultSeq = defaultSeq;
        wrap.objPrefix = prefix;

        mapRef.get(objectName).put(type, wrap);
    }

    /**to hold object vs naming seq */
    public class NamingSequenceWrapper{
        public String objPrefix = '';
        public String objExistingSeq = '';
        public String objDefaultSeq = '';
    }

    public static String getObjectPrefix(String objectApiName) {
        Schema.SObjectType objectType = tcpl_UtilityNamingConventionConstant.knownObjectTypes.get(objectApiName);
        // Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType != null) {
            return objectType.getDescribe().getKeyPrefix();
        }
        return null;
    }


    public static void setExtenralIdField(List<Sobject> objList, String objectApiName){
        if (objList == null || objList.isEmpty()) {
            return;
        }

        set<Id> recIds = new set<Id>();
        Map<String,String> accAndSecInvMap = new Map<String,String>();
        String fiscalYear = getLastTwoDigitForYear();
        map<String,String> accAndSapNo = new map<String,String>();
        for(Sobject rec : objList){
            recIds.add(rec.Id);
        }

        String accountRelField = formatQueryWithAccountField(objectApiName,'{0}');
        accountRelField = accountRelField.left(accountRelField.length() - 1) + 'r';
        String accountSapField = 'tcpl_customerSapNo__c';
        String externalIdField = 'tcpl_External_Id__c';
        String query = 'SELECT Id, Name, ' + accountRelField + '.' + accountSapField +
                       ' FROM ' + objectApiName + ' WHERE Id IN :recIds';
        System.debug('query>>'+query);
        List<SObject> queriedRecords = Database.query(query);
        System.debug('queriedRecords>>'+queriedRecords);
        for (SObject rec : queriedRecords) {
            System.debug('rec>>'+rec);
            // SObject accountRel = (SObject) rec.get(accountRelField);
            SObject accountRel = rec.getSObject(accountRelField);
            System.debug('accountRel>>'+rec);
            if (accountRel != null) {
                String sapNo = (String) accountRel.get(accountSapField);
                accAndSapNo.put(rec.Id, sapNo);
            }
        }

        for (SObject rec : objList) {
            String sapNo = accAndSapNo.get(rec.Id);
            if (sapNo != null) {
                String externalIdValue = (String) rec.get('Name') + '_' + sapNo + '_' + fiscalYear;
                rec.put(externalIdField, externalIdValue);
            }
        }
    }
    
    public static void firePlatformEvent(Map < id, Sobject > records, String objectName, String eventApiName) {
        try{
            List<SObject> eventList = new List<SObject>();
            Schema.SObjectType sObjType = tcpl_UtilityNamingConventionConstant.knownObjectTypes.get(eventApiName);
            // Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(eventApiName);
            set<Id> accIds = new set<Id>();
            String accFieldName = formatQueryWithAccountField(objectName,'{0}');

            Map<String, SObject> accountIdToAnyRecord = new Map<String, SObject>();

            for (Id recId : recOrds.keySet()) {
                SObject sob = recOrds.get(recId);
                String accountId = (String) sob.get(accFieldName);

                // Only store one record per account
                if (!accountIdToAnyRecord.containsKey(accountId)) {
                    accountIdToAnyRecord.put(accountId, sob);
                }
            }

            // Now generate one event per unique account
            // List<SObject> eventList = new List<SObject>();
            Set<String> accIdSet = new Set<String>();
            Set<String> invId = new Set<String>();
            tcpl_logger__c errorLogInstance;
            for (String accountId : accountIdToAnyRecord.keySet()) {
                SObject sob = accountIdToAnyRecord.get(accountId);
                Id recId = sob.Id; // You can optionally grab recId from sob if available

                SObject eventRecord = sObjType.newSObject();
                eventRecord.put('tcpl_AccountSFId__c', accountId);
                eventRecord.put('tcpl_objectName__c', objectName);
                eventRecord.put('tcpl_recordId__c', sob.Id); // Or recId, if needed

                eventList.add(eventRecord);
                accIdSet.add(accountId);
                invId.add(sob.Id);
            }

            // Publish only one event per account
            List<Database.SaveResult> results = EventBus.publish(eventList);
            Boolean enableDebugLogs = false;
            enableDebugLogs = System.Label.EnablePlatformEventLogger.equalsIgnoreCase('YES');
            if (enableDebugLogs) {
                errorLogInstance = tcpl_loggerUtility.returnLog(
                    'Info',
                    'tcpl_utilityForNamingConvntionV3',
                    'firePlatformEvent',
                    'firevents',
                    String.valueOf(eventList.size()),
                    'Total Invoice ' + invId.size() + '  ' + String.join(invId, ','),
                    'Total Accounts ' + accIdSet.size() + '  ' + String.join(accIdSet, ',')
                );
                insert errorLogInstance;
            }

            // /**used for debugging to be removed once tested */
            // tcpl_logger__c log = new tcpl_logger__c();
            // log.Class_Name__c = 'tcpl_utilityForNamingConvntionV3';
            // log.Method_Name__c = 'firePlatformEvent'+objectName;
            // log.Request_Body__c = JSON.serialize(eventList);
            // log.tcpl_Verbose__c = 'platFormEvent '+ String.valueOf(eventList.Size());
            // log.tcpl_Verbose2__c = JSON.serialize(results);
            // insert log;
            /**end */
        } 
        catch(exception ex){
            system.debug('Exception Occurred when firing platform event'+ex.getMessage());
        }
    }

    public class RecordsToUpdateNameWrap { 
        public string AccountSfId;
        public String recordId;
        public String objectName;
    }

    public static boolean lockOrUnlockRecords(Id accountId, Boolean updateRecords){
        try{
            List<tcpl_Invoice_Name_Population_Lock__c> invLock = [select id,tcpl_Distributor__c,tcpl_isLocked__c,CreatedDate,LastmodifiedDate from tcpl_Invoice_Name_Population_Lock__c where tcpl_Distributor__c =: accountId limit 1 FOR UPDATE];
            Boolean isRecordLock = false;
            //check if the child record is locked for more than an hour
            
                List<tcpl_Invoice_Name_Population_Lock__c> lockRecord;
            if (invLock.isEmpty()) {
                if(accountId != null){
                    //create instance of lock record
                    tcpl_Invoice_Name_Population_Lock__c createInvLockRec = new tcpl_Invoice_Name_Population_Lock__c();
                    createInvLockRec.tcpl_Distributor__c = accountId;
                    insert createInvLockRec;

                    lockRecord = [select id,tcpl_Distributor__c,tcpl_isLocked__c,CreatedDate,LastmodifiedDate from tcpl_Invoice_Name_Population_Lock__c where tcpl_Distributor__c =: accountId limit 1 FOR UPDATE];
                }
            } else {
                lockRecord = invLock;
            }
                
            
            if(lockRecord.size() > 0){
                Boolean isRecordLockedGreaterThanTwoMin = false;
                if(lockRecord[0].tcpl_isLocked__c){
                    isRecordLockedGreaterThanTwoMin = checkLockDuration(lockRecord[0].LastmodifiedDate);
                }

                if(updateRecords && lockRecord[0].tcpl_isLocked__c == true){//unlock record
                    lockRecord[0].tcpl_isLocked__c = false;
                    update lockRecord[0];
                    return isRecordLock;
                } else {
                    if(!lockRecord[0].tcpl_isLocked__c || isRecordLockedGreaterThanTwoMin){//lock the record and proceed with Invoice conversion
                        lockRecord[0].tcpl_isLocked__c = true;
                        update lockRecord[0]; // updating same acc if locked more than 2 min to update lastodifed Date to be able to pick for next transactions
                        return isRecordLock;
                    }
                    else{//record is locked 
                        isRecordLock = true;
                        return isRecordLock;
                    }
                }
            }else {
                 return true;
            }
        } catch(Exception e){
            //error while querying the child record or the record is already locked
            return true;
        }
    }

    public static boolean checkLockDuration(DateTime lastModified){
        Boolean isRecordLocked;
        DateTime currentTime = DateTime.now();
        System.debug('current time = '+currentTime);
        // Get the difference in milliseconds
        //Long diffInMillis = lastModified.getTime() - currentTime.getTime();
        Long diffInMillis = Math.abs(lastModified.getTime() - currentTime.getTime());
        // Convert to hours
        // Decimal diffInHours = diffInMillis / (1000 * 60 * 60);
        Decimal diffInMinutes = diffInMillis / (1000 * 60);
        //check if the result is greater than an hour
        if (diffInMinutes > 2) {
            return isRecordLocked = true;
        } else {
            return isRecordLocked = false;
        }
    }

    public static void methodToCallToRunFailedRecName(String ObjectName,List<Id> recIds,String accId){
        List<RecordsToUpdateNameWrap> recToUpdateList = new List<RecordsToUpdateNameWrap>();
        if(!recIds.isEmpty()){
            for(Id recId : recIds){
                RecordsToUpdateNameWrap recToUpdate = new RecordsToUpdateNameWrap();
                recToUpdate.objectName = ObjectName;
                recToUpdate.recordId = recId;
                recToUpdate.AccountSfId = accId;
                recToUpdateList.add(recToUpdate);
            }
        }

        if(!recToUpdateList.isEmpty()){
            handlePlatformEvent(recToUpdateList);
        }
    }
}