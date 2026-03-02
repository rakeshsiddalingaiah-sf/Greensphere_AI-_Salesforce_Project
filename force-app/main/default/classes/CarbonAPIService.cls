/**
 * @description External API integration service for CarbonInterface.com.
 *              Fetches real-time emission factors for various activity types.
 *              Uses Named Credential "CarbonInterface_API" for authentication.
 * @author      GreenSphere AI
 * @version     1.0
 */
public with sharing class CarbonAPIService {

    private static final String NAMED_CREDENTIAL = 'callout:CarbonInterface_API';
    private static final String ESTIMATES_ENDPOINT = '/api/v1/estimates';

    /**
     * @description Calculates electricity emissions via CarbonInterface API.
     * @param electricityValue kWh consumed
     * @param country          ISO country code
     * @param state            Optional state code (for US)
     * @return CarbonAPIResult with CO2e in kg
     */
    @AuraEnabled
    public static CarbonAPIResult calculateElectricityEmissions(
        Decimal electricityValue, String country, String state
    ) {
        Map<String, Object> requestBody = new Map<String, Object>{
            'type'                 => 'electricity',
            'electricity_unit'    => 'kwh',
            'electricity_value'   => electricityValue,
            'country'             => country,
            'state'               => String.isNotBlank(state) ? state : null
        };
        return makeAPICall(requestBody);
    }

    /**
     * @description Calculates flight emissions via CarbonInterface API.
     * @param passengers Number of passengers
     * @param legs       List of leg maps with departure/destination IATA codes
     * @return CarbonAPIResult with CO2e in kg
     */
    @AuraEnabled
    public static CarbonAPIResult calculateFlightEmissions(Integer passengers, List<Map<String, String>> legs) {
        Map<String, Object> requestBody = new Map<String, Object>{
            'type'       => 'flight',
            'passengers' => passengers,
            'legs'       => legs
        };
        return makeAPICall(requestBody);
    }

    /**
     * @description Calculates fuel combustion emissions via CarbonInterface API.
     * @param fuelSourceUnit  litre / gallon / cubic_metre
     * @param fuelSourceValue Quantity
     * @param fuelSourceType  ng / lpg / diesel / petrol
     * @return CarbonAPIResult with CO2e in kg
     */
    @AuraEnabled
    public static CarbonAPIResult calculateFuelEmissions(
        String fuelSourceUnit, Decimal fuelSourceValue, String fuelSourceType
    ) {
        Map<String, Object> requestBody = new Map<String, Object>{
            'type'              => 'fuel_combustion',
            'fuel_source_type'  => fuelSourceType,
            'fuel_source_unit'  => fuelSourceUnit,
            'fuel_source_value' => fuelSourceValue
        };
        return makeAPICall(requestBody);
    }

    /**
     * @description Core HTTP callout to CarbonInterface API.
     */
    @TestVisible
    private static CarbonAPIResult makeAPICall(Map<String, Object> requestBody) {
        CarbonAPIResult result = new CarbonAPIResult();

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL + ESTIMATES_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setBody(JSON.serialize(requestBody));
            req.setTimeout(10000);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 201) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Map<String, Object> data = (Map<String, Object>) responseMap.get('data');
                Map<String, Object> attributes = (Map<String, Object>) data.get('attributes');

                result.success         = true;
                result.carbonKg        = (Decimal) attributes.get('carbon_kg');
                result.carbonLb        = (Decimal) attributes.get('carbon_lb');
                result.carbonMt        = (Decimal) attributes.get('carbon_mt');
                result.estimatedAt     = (String) attributes.get('estimated_at');
            } else {
                result.success      = false;
                result.errorMessage = 'API returned status: ' + res.getStatusCode() + ' - ' + res.getStatus();
            }
        } catch (CalloutException e) {
            result.success      = false;
            result.errorMessage = 'Callout failed: ' + e.getMessage();
        } catch (Exception e) {
            result.success      = false;
            result.errorMessage = 'Unexpected error: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Response wrapper for CarbonInterface API results.
     */
    public class CarbonAPIResult {
        @AuraEnabled public Boolean success       { get; set; }
        @AuraEnabled public Decimal carbonKg      { get; set; }
        @AuraEnabled public Decimal carbonLb      { get; set; }
        @AuraEnabled public Decimal carbonMt      { get; set; }
        @AuraEnabled public String  estimatedAt   { get; set; }
        @AuraEnabled public String  errorMessage  { get; set; }

        public CarbonAPIResult() {
            success = false;
            carbonKg = 0;
            carbonLb = 0;
            carbonMt = 0;
        }
    }
}
