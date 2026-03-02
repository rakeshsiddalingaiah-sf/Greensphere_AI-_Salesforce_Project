/**
 * SETUP SCRIPT 1: Schedule nightly emission processing
 * Run this once in Anonymous Apex after deployment.
 */
BulkEmissionProcessor.scheduleNightly();

/**
 * SETUP SCRIPT 2: Run immediate compliance analysis for an account
 * Replace ACCOUNT_ID with a real Account Id.
 */
// Id accountId = 'ACCOUNT_ID';
// List<ComplianceRiskEngine.ComplianceRiskResult> results =
//     ComplianceRiskEngine.analyzeComplianceRisk(accountId);
// for (ComplianceRiskEngine.ComplianceRiskResult r : results) {
//     System.debug(r.regulationName + ': ' + r.complianceProbability + '% — ' + r.status);
// }

/**
 * SETUP SCRIPT 3: Generate AI report for an account
 */
// ESGReportGeneratorService.ESGReport report =
//     ESGReportGeneratorService.generateExecutiveSummary(accountId, 2026);
// System.debug('AI Report: ' + report.aiSummary);
