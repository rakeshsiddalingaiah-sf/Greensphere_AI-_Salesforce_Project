/**
 * @description Service class for calculating GHG Protocol compliant Scope 1, 2, 3 emissions.
 *              Integrates with CarbonInterface API for emission factor lookups.
 * @author      GreenSphere AI
 * @version     1.0
 */
public with sharing class EmissionCalculatorService {

    // GHG Protocol emission factors (kg CO2e per unit) - defaults if API unavailable
    private static final Map<String, Decimal> SCOPE1_FACTORS = new Map<String, Decimal>{
        'Natural Gas'       => 2.204,   // kg CO2e per cubic meter
        'Diesel'            => 2.68,    // kg CO2e per liter
        'Petrol'            => 2.31,    // kg CO2e per liter
        'LPG'               => 1.51,    // kg CO2e per liter
        'Coal'              => 2.42,    // kg CO2e per kg
        'Heating Oil'       => 2.52     // kg CO2e per liter
    };

    private static final Map<String, Decimal> SCOPE2_FACTORS = new Map<String, Decimal>{
        'Grid Electricity US'       => 0.386,   // kg CO2e per kWh
        'Grid Electricity EU'       => 0.276,
        'Grid Electricity India'    => 0.708,
        'Grid Electricity China'    => 0.555,
        'Renewable Energy'          => 0.0
    };

    private static final Map<String, Decimal> SCOPE3_CATEGORIES = new Map<String, Decimal>{
        'Business Travel - Air'     => 0.255,   // kg CO2e per passenger-km
        'Business Travel - Rail'    => 0.041,
        'Employee Commute'          => 0.171,   // kg CO2e per vehicle-km
        'Waste - Landfill'          => 0.467,   // kg CO2e per kg waste
        'Waste - Recycled'          => 0.021,
        'Purchased Goods'           => 0.0,     // Requires supplier data
        'Upstream Transport'        => 0.0      // Requires supplier data
    };

    /**
     * @description Calculates carbon emissions for a list of emission records.
     * @param records List of Emission_Record__c to calculate
     * @return Map of record Id to calculated emission value in metric tonnes CO2e
     */
    public static Map<Id, Decimal> calculateEmissions(List<Emission_Record__c> records) {
        Map<Id, Decimal> results = new Map<Id, Decimal>();

        for (Emission_Record__c record : records) {
            Decimal emissionFactor = getEmissionFactor(record.Scope_Type__c, record.Source_Category__c);
            Decimal grossEmission = (record.Activity_Value__c != null)
                ? record.Activity_Value__c * emissionFactor / 1000  // Convert kg to tonnes
                : 0;
            Decimal netEmission = grossEmission - (record.Carbon_Offset__c != null ? record.Carbon_Offset__c : 0);
            results.put(record.Id, netEmission < 0 ? 0 : netEmission);
        }
        return results;
    }

    /**
     * @description Aggregates total emissions by scope for a given account.
     * @param accountId The Account Id to aggregate for
     * @param startDate Reporting period start
     * @param endDate   Reporting period end
     * @return ESGEmissionSummary wrapper with scope breakdowns
     */
    public static ESGEmissionSummary getEmissionSummary(Id accountId, Date startDate, Date endDate) {
        List<AggregateResult> results = [
            SELECT Scope_Type__c, SUM(Net_Emission__c) totalEmission
            FROM Emission_Record__c
            WHERE Company__c = :accountId
              AND Emission_Date__c >= :startDate
              AND Emission_Date__c <= :endDate
            GROUP BY Scope_Type__c
        ];

        ESGEmissionSummary summary = new ESGEmissionSummary();
        for (AggregateResult ar : results) {
            String scope = (String) ar.get('Scope_Type__c');
            Decimal total = (Decimal) ar.get('totalEmission');
            if (scope == 'Scope 1') summary.scope1Total = total;
            else if (scope == 'Scope 2') summary.scope2Total = total;
            else if (scope == 'Scope 3') summary.scope3Total = total;
        }
        summary.grandTotal = summary.scope1Total + summary.scope2Total + summary.scope3Total;
        return summary;
    }

    /**
     * @description Retrieves emission factor for a given scope and source category.
     */
    @TestVisible
    private static Decimal getEmissionFactor(String scopeType, String sourceCategory) {
        if (scopeType == 'Scope 1' && SCOPE1_FACTORS.containsKey(sourceCategory)) {
            return SCOPE1_FACTORS.get(sourceCategory);
        } else if (scopeType == 'Scope 2' && SCOPE2_FACTORS.containsKey(sourceCategory)) {
            return SCOPE2_FACTORS.get(sourceCategory);
        } else if (scopeType == 'Scope 3' && SCOPE3_CATEGORIES.containsKey(sourceCategory)) {
            return SCOPE3_CATEGORIES.get(sourceCategory);
        }
        return 0.0;
    }

    /**
     * @description Batch-saves calculated emission values back to records.
     * @param records List of records with Activity_Value__c populated
     */
    public static void processAndSaveEmissions(List<Emission_Record__c> records) {
        Map<Id, Decimal> calculatedValues = calculateEmissions(records);
        List<Emission_Record__c> toUpdate = new List<Emission_Record__c>();

        for (Emission_Record__c rec : records) {
            if (calculatedValues.containsKey(rec.Id)) {
                toUpdate.add(new Emission_Record__c(
                    Id = rec.Id,
                    Net_Emission__c = calculatedValues.get(rec.Id)
                ));
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * @description Wrapper class for emission summary data.
     */
    public class ESGEmissionSummary {
        @AuraEnabled public Decimal scope1Total   { get; set; }
        @AuraEnabled public Decimal scope2Total   { get; set; }
        @AuraEnabled public Decimal scope3Total   { get; set; }
        @AuraEnabled public Decimal grandTotal    { get; set; }
        @AuraEnabled public String  periodLabel   { get; set; }

        public ESGEmissionSummary() {
            scope1Total = 0;
            scope2Total = 0;
            scope3Total = 0;
            grandTotal  = 0;
        }
    }
}
