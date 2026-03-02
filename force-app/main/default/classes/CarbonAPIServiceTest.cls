/**
 * @description Test class for CarbonAPIService with mock HTTP callouts.
 * @author      GreenSphere AI
 */
@IsTest
private class CarbonAPIServiceTest {

    /**
     * @description Mock HTTP response for CarbonInterface API.
     */
    private class CarbonAPIMock implements HttpCalloutMock {
        private Integer statusCode;
        private String  responseBody;

        CarbonAPIMock(Integer statusCode, String body) {
            this.statusCode   = statusCode;
            this.responseBody = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    private static String SUCCESSFUL_RESPONSE = '{"data":{"id":"abc123","type":"estimate","attributes":{"carbon_kg":12.5,"carbon_lb":27.6,"carbon_mt":0.0125,"estimated_at":"2026-01-01T00:00:00.000Z"}}}';
    private static String ERROR_RESPONSE = '{"message":"Invalid request parameters"}';

    @IsTest
    static void testCalculateElectricityEmissions_Success() {
        Test.setMock(HttpCalloutMock.class, new CarbonAPIMock(201, SUCCESSFUL_RESPONSE));

        Test.startTest();
        CarbonAPIService.CarbonAPIResult result =
            CarbonAPIService.calculateElectricityEmissions(1000, 'US', 'CA');
        Test.stopTest();

        Assert.isTrue(result.success, 'API call should succeed');
        Assert.areEqual(12.5, result.carbonKg, 'Carbon kg should match mock response');
        Assert.areEqual(0.0125, result.carbonMt, 'Carbon mt should match mock response');
    }

    @IsTest
    static void testCalculateFlightEmissions_Success() {
        Test.setMock(HttpCalloutMock.class, new CarbonAPIMock(201, SUCCESSFUL_RESPONSE));
        List<Map<String, String>> legs = new List<Map<String, String>>{
            new Map<String, String>{'departure_airport' => 'SFO', 'destination_airport' => 'JFK'}
        };

        Test.startTest();
        CarbonAPIService.CarbonAPIResult result =
            CarbonAPIService.calculateFlightEmissions(2, legs);
        Test.stopTest();

        Assert.isTrue(result.success, 'Flight emissions call should succeed');
        Assert.areEqual(12.5, result.carbonKg, 'Carbon kg should match');
    }

    @IsTest
    static void testCalculateFuelEmissions_Success() {
        Test.setMock(HttpCalloutMock.class, new CarbonAPIMock(201, SUCCESSFUL_RESPONSE));

        Test.startTest();
        CarbonAPIService.CarbonAPIResult result =
            CarbonAPIService.calculateFuelEmissions('litre', 500, 'diesel');
        Test.stopTest();

        Assert.isTrue(result.success, 'Fuel emissions call should succeed');
    }

    @IsTest
    static void testAPICallout_ErrorResponse() {
        Test.setMock(HttpCalloutMock.class, new CarbonAPIMock(422, ERROR_RESPONSE));

        Test.startTest();
        CarbonAPIService.CarbonAPIResult result =
            CarbonAPIService.calculateElectricityEmissions(1000, 'ZZ', null);
        Test.stopTest();

        Assert.isFalse(result.success, 'Failed API should return false');
        Assert.isTrue(result.errorMessage.contains('422'), 'Error message should contain status code');
    }

    @IsTest
    static void testAPICallout_CalloutException() {
        Test.setMock(HttpCalloutMock.class, new CarbonAPIMock(503, 'Service Unavailable'));

        Test.startTest();
        CarbonAPIService.CarbonAPIResult result =
            CarbonAPIService.calculateElectricityEmissions(1000, 'US', null);
        Test.stopTest();

        Assert.isFalse(result.success, 'Non-201 response should be failure');
    }
}
