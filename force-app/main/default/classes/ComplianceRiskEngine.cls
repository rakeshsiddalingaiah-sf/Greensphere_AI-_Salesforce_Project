/**
 * @description Predictive compliance risk engine. Calculates compliance probability
 *              scores based on historical data, regulation thresholds (Custom Metadata),
 *              emission trends, and submission completeness.
 * @author      GreenSphere AI
 * @version     1.0
 */
public with sharing class ComplianceRiskEngine {

    /**
     * @description Runs compliance risk analysis for a given account across all active regulations.
     * @param accountId Account to analyze
     * @return List of ComplianceRiskResult for each regulation
     */
    @AuraEnabled(cacheable=false)
    public static List<ComplianceRiskResult> analyzeComplianceRisk(Id accountId) {
        // Load regulation thresholds from Custom Metadata
        List<ESG_Regulation_Threshold__mdt> regulations = [
            SELECT Label, Regulation_Code__c, Max_Emission_Tonnes__c,
                   Min_ESG_Score__c, Report_Frequency__c, Penalty_Per_Tonne__c
            FROM ESG_Regulation_Threshold__mdt
            WHERE IsActive__c = true
        ];

        // Get latest ESG score
        List<ESG_Score__c> scores = [
            SELECT Overall_Score__c, Environmental_Score__c
            FROM ESG_Score__c
            WHERE Company__c = :accountId
            ORDER BY Score_Date__c DESC
            LIMIT 1
        ];

        // Get current year emissions
        Date startOfYear = Date.newInstance(Date.today().year(), 1, 1);
        EmissionCalculatorService.ESGEmissionSummary emissions =
            EmissionCalculatorService.getEmissionSummary(accountId, startOfYear, Date.today());

        // Get existing compliance records to update
        Map<String, Compliance_Record__c> existingRecords = getExistingComplianceRecords(accountId);

        List<ComplianceRiskResult> results   = new List<ComplianceRiskResult>();
        List<Compliance_Record__c> toUpsert  = new List<Compliance_Record__c>();

        Decimal currentScore     = scores.isEmpty() ? 0 : scores[0].Overall_Score__c;
        Decimal currentEmissions = emissions.grandTotal;

        for (ESG_Regulation_Threshold__mdt reg : regulations) {
            Decimal probability = calculateComplianceProbability(
                currentEmissions, currentScore, reg, emissions
            );
            String status = deriveStatus(probability);
            Decimal penaltyRisk = calculatePenaltyRisk(
                currentEmissions, reg.Max_Emission_Tonnes__c, reg.Penalty_Per_Tonne__c
            );

            ComplianceRiskResult res = new ComplianceRiskResult();
            res.regulationCode      = reg.Regulation_Code__c;
            res.regulationName      = reg.Label;
            res.complianceProbability = probability;
            res.status              = status;
            res.penaltyRiskUSD      = penaltyRisk;
            res.currentEmissions    = currentEmissions;
            res.thresholdEmissions  = reg.Max_Emission_Tonnes__c;
            res.currentScore        = currentScore;
            res.minRequiredScore    = reg.Min_ESG_Score__c;
            results.add(res);

            // Build Compliance_Record__c for upsert
            Compliance_Record__c compRec = existingRecords.containsKey(reg.Regulation_Code__c)
                ? existingRecords.get(reg.Regulation_Code__c)
                : new Compliance_Record__c(
                    Company__c   = accountId,
                    Regulation__c = reg.Label
                );
            compRec.Compliance_Probability__c = probability;
            compRec.Status__c                 = status;
            compRec.Penalty_Risk_USD__c       = penaltyRisk;
            toUpsert.add(compRec);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }

        return results;
    }

    /**
     * @description Returns compliance dashboard summary for LWC.
     */
    @AuraEnabled(cacheable=true)
    public static ComplianceDashboardSummary getComplianceSummary(Id accountId) {
        List<Compliance_Record__c> records = [
            SELECT Status__c, Compliance_Probability__c, Penalty_Risk_USD__c, Regulation__c
            FROM Compliance_Record__c
            WHERE Company__c = :accountId
        ];

        ComplianceDashboardSummary summary = new ComplianceDashboardSummary();
        summary.totalRegulations = records.size();
        for (Compliance_Record__c r : records) {
            if (r.Status__c == 'On Track') summary.onTrackCount++;
            else if (r.Status__c == 'At Risk') summary.atRiskCount++;
            else if (r.Status__c == 'Overdue') summary.overdueCount++;
            summary.totalPenaltyExposure += (r.Penalty_Risk_USD__c != null ? r.Penalty_Risk_USD__c : 0);
        }
        return summary;
    }

    /**
     * @description Calculates compliance probability using weighted scoring model.
     */
    @TestVisible
    private static Decimal calculateComplianceProbability(
        Decimal currentEmissions,
        Decimal currentScore,
        ESG_Regulation_Threshold__mdt reg,
        EmissionCalculatorService.ESGEmissionSummary emissions
    ) {
        Decimal probability = 100;

        // Emission threshold factor (max -50 points)
        if (reg.Max_Emission_Tonnes__c != null && reg.Max_Emission_Tonnes__c > 0) {
            Decimal emissionRatio = currentEmissions / reg.Max_Emission_Tonnes__c;
            if (emissionRatio > 1.2)        probability -= 50;
            else if (emissionRatio > 1.0)   probability -= 30;
            else if (emissionRatio > 0.9)   probability -= 10;
        }

        // ESG score factor (max -30 points)
        if (reg.Min_ESG_Score__c != null && reg.Min_ESG_Score__c > 0) {
            Decimal scoreDeficit = reg.Min_ESG_Score__c - currentScore;
            if (scoreDeficit > 20)      probability -= 30;
            else if (scoreDeficit > 10) probability -= 15;
            else if (scoreDeficit > 0)  probability -= 5;
        }

        // Scope 3 data completeness factor (max -20 points)
        if (emissions.scope3Total == 0) probability -= 20;
        else if (emissions.scope3Total < emissions.scope1Total * 0.5) probability -= 10;

        return probability.setScale(1) < 0 ? 0 : probability.setScale(1);
    }

    private static String deriveStatus(Decimal probability) {
        if (probability >= 75) return 'On Track';
        if (probability >= 50) return 'At Risk';
        return 'Overdue';
    }

    private static Decimal calculatePenaltyRisk(
        Decimal actualEmissions, Decimal threshold, Decimal penaltyPerTonne
    ) {
        if (threshold == null || penaltyPerTonne == null || actualEmissions <= threshold) return 0;
        return ((actualEmissions - threshold) * penaltyPerTonne).setScale(2);
    }

    private static Map<String, Compliance_Record__c> getExistingComplianceRecords(Id accountId) {
        Map<String, Compliance_Record__c> result = new Map<String, Compliance_Record__c>();
        for (Compliance_Record__c r : [
            SELECT Id, Regulation__c, Status__c, Compliance_Probability__c, Penalty_Risk_USD__c
            FROM Compliance_Record__c
            WHERE Company__c = :accountId
        ]) {
            result.put(r.Regulation__c, r);
        }
        return result;
    }

    public class ComplianceRiskResult {
        @AuraEnabled public String  regulationCode          { get; set; }
        @AuraEnabled public String  regulationName          { get; set; }
        @AuraEnabled public Decimal complianceProbability   { get; set; }
        @AuraEnabled public String  status                  { get; set; }
        @AuraEnabled public Decimal penaltyRiskUSD          { get; set; }
        @AuraEnabled public Decimal currentEmissions        { get; set; }
        @AuraEnabled public Decimal thresholdEmissions      { get; set; }
        @AuraEnabled public Decimal currentScore            { get; set; }
        @AuraEnabled public Decimal minRequiredScore        { get; set; }
    }

    public class ComplianceDashboardSummary {
        @AuraEnabled public Integer totalRegulations     { get; set; }
        @AuraEnabled public Integer onTrackCount         { get; set; }
        @AuraEnabled public Integer atRiskCount          { get; set; }
        @AuraEnabled public Integer overdueCount         { get; set; }
        @AuraEnabled public Decimal totalPenaltyExposure { get; set; }

        public ComplianceDashboardSummary() {
            totalRegulations     = 0;
            onTrackCount         = 0;
            atRiskCount          = 0;
            overdueCount         = 0;
            totalPenaltyExposure = 0;
        }
    }
}
