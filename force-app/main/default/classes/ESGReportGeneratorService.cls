/**
 * @description Service for generating AI-powered ESG reports using Einstein Prompt Builder.
 *              Connects to ConnectApi.EinsteinAI to invoke named prompt templates
 *              and returns formatted executive summaries.
 * @author      GreenSphere AI
 * @version     1.0
 */
public with sharing class ESGReportGeneratorService {

    private static final String EXEC_SUMMARY_PROMPT   = 'ESG_Executive_Summary';
    private static final String SUPPLIER_RISK_PROMPT  = 'Supplier_Risk_Analysis';
    private static final String COMPLIANCE_PROMPT     = 'Compliance_Forecast';

    /**
     * @description Generates an executive ESG summary for an account using Einstein AI.
     * @param accountId Account to generate report for
     * @param periodYear Reporting year
     * @return ESGReport wrapper with AI-generated content
     */
    @AuraEnabled
    public static ESGReport generateExecutiveSummary(Id accountId, Integer periodYear) {
        // Pull emission summary
        Date startDate = Date.newInstance(periodYear, 1, 1);
        Date endDate   = Date.newInstance(periodYear, 12, 31);
        EmissionCalculatorService.ESGEmissionSummary emissions =
            EmissionCalculatorService.getEmissionSummary(accountId, startDate, endDate);

        // Pull ESG scores
        List<ESG_Score__c> scores = [
            SELECT Overall_Score__c, Environmental_Score__c,
                   Social_Score__c, Governance_Score__c, Score_Date__c
            FROM ESG_Score__c
            WHERE Company__c = :accountId
            ORDER BY Score_Date__c DESC
            LIMIT 1
        ];

        // Pull compliance records
        List<Compliance_Record__c> complianceRecs = [
            SELECT Regulation__c, Compliance_Probability__c, Status__c, Penalty_Risk_USD__c
            FROM Compliance_Record__c
            WHERE Company__c = :accountId
            ORDER BY Due_Date__c ASC
            LIMIT 5
        ];

        // Build prompt context
        String promptContext = buildPromptContext(emissions, scores, complianceRecs, periodYear);

        // Call Einstein AI
        String aiSummary = invokeEinsteinPrompt(EXEC_SUMMARY_PROMPT, promptContext);

        // Build and save ESG score record with AI summary
        if (!scores.isEmpty()) {
            ESG_Score__c scoreToUpdate = scores[0].clone(true, true, false, false);
            scoreToUpdate.AI_Summary__c = aiSummary;
            update scoreToUpdate;
        }

        // Return report object
        ESGReport report = new ESGReport();
        report.accountId        = accountId;
        report.periodYear       = periodYear;
        report.aiSummary        = aiSummary;
        report.totalEmissions   = emissions.grandTotal;
        report.scope1           = emissions.scope1Total;
        report.scope2           = emissions.scope2Total;
        report.scope3           = emissions.scope3Total;
        report.overallScore     = scores.isEmpty() ? null : scores[0].Overall_Score__c;
        report.generatedDate    = DateTime.now();
        return report;
    }

    /**
     * @description Generates AI-powered supplier risk narrative.
     * @param supplierAccountId Supplier Account Id
     * @return String narrative from Einstein AI
     */
    @AuraEnabled
    public static String generateSupplierRiskNarrative(Id supplierAccountId) {
        List<Supplier_Emission__c> supplierData = [
            SELECT Supplier__r.Name, Risk_Score__c, ESG_Rating__c,
                   Scope3_Contribution__c, Compliance_Status__c, Last_Audit_Date__c
            FROM Supplier_Emission__c
            WHERE Supplier__c = :supplierAccountId
            LIMIT 1
        ];

        if (supplierData.isEmpty()) {
            return 'No supplier data available for analysis.';
        }

        String context = JSON.serialize(supplierData[0]);
        return invokeEinsteinPrompt(SUPPLIER_RISK_PROMPT, context);
    }

    /**
     * @description Core Einstein Prompt Builder invocation.
     *              Uses ConnectApi.EinsteinAI to call a named prompt template.
     */
    @TestVisible
    private static String invokeEinsteinPrompt(String promptName, String contextData) {
        try {
            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.additionalConfig.applicationName = 'GreenSphereESG';
            input.isPreview = false;

            Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>();
            ConnectApi.WrappedValue contextValue = new ConnectApi.WrappedValue();
            contextValue.value = contextData;
            valueMap.put('ESG_Context', contextValue);
            input.inputParams = valueMap;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinAI.generateMessagesForPromptTemplate(promptName, input);

            if (result != null && result.generations != null && !result.generations.isEmpty()) {
                return result.generations[0].text;
            }
        } catch (Exception e) {
            System.debug('Einstein API Error: ' + e.getMessage());
            return generateFallbackSummary(contextData);
        }
        return 'Report generation unavailable. Please configure Einstein AI in Setup.';
    }

    /**
     * @description Fallback rule-based summary when Einstein is unavailable.
     */
    private static String generateFallbackSummary(String contextData) {
        return 'ESG Report Summary: Analysis based on submitted data. '
             + 'Please configure Einstein Prompt Builder for AI-enhanced narratives. '
             + 'Raw data context: ' + contextData.abbreviate(200);
    }

    /**
     * @description Builds structured context string for Einstein prompt.
     */
    private static String buildPromptContext(
        EmissionCalculatorService.ESGEmissionSummary emissions,
        List<ESG_Score__c> scores,
        List<Compliance_Record__c> complianceRecs,
        Integer year
    ) {
        Map<String, Object> context = new Map<String, Object>{
            'year'             => year,
            'scope1_emissions' => emissions.scope1Total,
            'scope2_emissions' => emissions.scope2Total,
            'scope3_emissions' => emissions.scope3Total,
            'total_emissions'  => emissions.grandTotal,
            'esg_score'        => scores.isEmpty() ? 'N/A' : scores[0].Overall_Score__c,
            'env_score'        => scores.isEmpty() ? 'N/A' : scores[0].Environmental_Score__c,
            'social_score'     => scores.isEmpty() ? 'N/A' : scores[0].Social_Score__c,
            'gov_score'        => scores.isEmpty() ? 'N/A' : scores[0].Governance_Score__c,
            'compliance_count' => complianceRecs.size(),
            'at_risk_count'    => getAtRiskCount(complianceRecs)
        };
        return JSON.serialize(context);
    }

    private static Integer getAtRiskCount(List<Compliance_Record__c> recs) {
        Integer count = 0;
        for (Compliance_Record__c r : recs) {
            if (r.Status__c == 'At Risk' || r.Status__c == 'Overdue') count++;
        }
        return count;
    }

    /**
     * @description ESG Report data wrapper for LWC consumption.
     */
    public class ESGReport {
        @AuraEnabled public Id       accountId      { get; set; }
        @AuraEnabled public Integer  periodYear     { get; set; }
        @AuraEnabled public String   aiSummary      { get; set; }
        @AuraEnabled public Decimal  totalEmissions { get; set; }
        @AuraEnabled public Decimal  scope1         { get; set; }
        @AuraEnabled public Decimal  scope2         { get; set; }
        @AuraEnabled public Decimal  scope3         { get; set; }
        @AuraEnabled public Decimal  overallScore   { get; set; }
        @AuraEnabled public DateTime generatedDate  { get; set; }
    }
}
