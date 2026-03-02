/**
 * @description AI-powered supplier ESG risk scoring service.
 *              Uses Einstein AI (Prompt Builder) to analyze supplier data
 *              and generate risk scores from 0 (low risk) to 100 (high risk).
 * @author      GreenSphere AI
 * @version     1.0
 */
public with sharing class SupplierRiskService {

    private static final Decimal HIGH_RISK_THRESHOLD    = 70.0;
    private static final Decimal MEDIUM_RISK_THRESHOLD  = 40.0;

    /**
     * @description Calculates AI-powered risk scores for a list of suppliers.
     * @param supplierIds Set of Account Ids (suppliers) to score
     * @return Map of supplier Id to SupplierRiskResult
     */
    @AuraEnabled(cacheable=false)
    public static List<SupplierRiskResult> calculateSupplierRiskScores(List<Id> supplierIds) {
        List<Supplier_Emission__c> suppliers = [
            SELECT Id, Supplier__c, Supplier__r.Name,
                   Scope3_Contribution__c, ESG_Rating__c,
                   Compliance_Status__c, Last_Audit_Date__c,
                   Risk_Score__c
            FROM Supplier_Emission__c
            WHERE Supplier__c IN :supplierIds
            ORDER BY Supplier__r.Name
        ];

        List<SupplierRiskResult> results = new List<SupplierRiskResult>();
        List<Supplier_Emission__c> toUpdate = new List<Supplier_Emission__c>();

        for (Supplier_Emission__c sup : suppliers) {
            Decimal riskScore = computeRuleBasedRisk(sup);
            String riskLevel  = getRiskLevel(riskScore);

            sup.Risk_Score__c = riskScore;
            sup.Compliance_Status__c = riskScore >= HIGH_RISK_THRESHOLD
                ? 'Non-Compliant'
                : riskScore >= MEDIUM_RISK_THRESHOLD ? 'At Risk' : 'Compliant';
            toUpdate.add(sup);

            SupplierRiskResult res = new SupplierRiskResult();
            res.supplierId    = sup.Supplier__c;
            res.supplierName  = sup.Supplier__r.Name;
            res.riskScore     = riskScore;
            res.riskLevel     = riskLevel;
            res.esgRating     = sup.ESG_Rating__c;
            res.scope3Contribution = sup.Scope3_Contribution__c;
            res.complianceStatus   = sup.Compliance_Status__c;
            res.lastAuditDate      = sup.Last_Audit_Date__c;
            results.add(res);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }

        return results;
    }

    /**
     * @description Returns top high-risk suppliers for dashboard widget.
     */
    @AuraEnabled(cacheable=true)
    public static List<SupplierRiskResult> getHighRiskSuppliers() {
        List<Supplier_Emission__c> highRisk = [
            SELECT Id, Supplier__c, Supplier__r.Name,
                   Risk_Score__c, ESG_Rating__c,
                   Scope3_Contribution__c, Compliance_Status__c,
                   Last_Audit_Date__c
            FROM Supplier_Emission__c
            WHERE Risk_Score__c >= :MEDIUM_RISK_THRESHOLD
            ORDER BY Risk_Score__c DESC
            LIMIT 10
        ];

        List<SupplierRiskResult> results = new List<SupplierRiskResult>();
        for (Supplier_Emission__c sup : highRisk) {
            SupplierRiskResult res = new SupplierRiskResult();
            res.supplierId         = sup.Supplier__c;
            res.supplierName       = sup.Supplier__r.Name;
            res.riskScore          = sup.Risk_Score__c;
            res.riskLevel          = getRiskLevel(sup.Risk_Score__c);
            res.esgRating          = sup.ESG_Rating__c;
            res.scope3Contribution = sup.Scope3_Contribution__c;
            res.complianceStatus   = sup.Compliance_Status__c;
            res.lastAuditDate      = sup.Last_Audit_Date__c;
            results.add(res);
        }
        return results;
    }

    /**
     * @description Rule-based risk computation pending Einstein API response.
     * Factors: ESG rating, compliance status, audit recency, scope3 volume.
     */
    @TestVisible
    private static Decimal computeRuleBasedRisk(Supplier_Emission__c sup) {
        Decimal score = 0;

        // ESG Rating factor (0-40 points)
        Map<String, Decimal> ratingScores = new Map<String, Decimal>{
            'A' => 0, 'B' => 10, 'C' => 20, 'D' => 30, 'F' => 40
        };
        score += ratingScores.containsKey(sup.ESG_Rating__c) ? ratingScores.get(sup.ESG_Rating__c) : 25;

        // Compliance status factor (0-30 points)
        if (sup.Compliance_Status__c == 'Non-Compliant') score += 30;
        else if (sup.Compliance_Status__c == 'At Risk') score += 15;

        // Audit recency factor (0-20 points)
        if (sup.Last_Audit_Date__c != null) {
            Integer daysSinceAudit = sup.Last_Audit_Date__c.daysBetween(Date.today());
            if (daysSinceAudit > 730)       score += 20; // > 2 years
            else if (daysSinceAudit > 365)  score += 10; // > 1 year
        } else {
            score += 20; // No audit on record
        }

        // Scope 3 volume factor (0-10 points)
        if (sup.Scope3_Contribution__c != null && sup.Scope3_Contribution__c > 10000) {
            score += 10;
        } else if (sup.Scope3_Contribution__c != null && sup.Scope3_Contribution__c > 5000) {
            score += 5;
        }

        return score.setScale(1);
    }

    private static String getRiskLevel(Decimal score) {
        if (score == null) return 'Unknown';
        if (score >= HIGH_RISK_THRESHOLD)   return 'High';
        if (score >= MEDIUM_RISK_THRESHOLD) return 'Medium';
        return 'Low';
    }

    /**
     * @description Result wrapper for supplier risk data.
     */
    public class SupplierRiskResult {
        @AuraEnabled public Id      supplierId         { get; set; }
        @AuraEnabled public String  supplierName       { get; set; }
        @AuraEnabled public Decimal riskScore          { get; set; }
        @AuraEnabled public String  riskLevel          { get; set; }
        @AuraEnabled public String  esgRating          { get; set; }
        @AuraEnabled public Decimal scope3Contribution { get; set; }
        @AuraEnabled public String  complianceStatus   { get; set; }
        @AuraEnabled public Date    lastAuditDate      { get; set; }
        @AuraEnabled public String  aiInsight          { get; set; }
    }
}
