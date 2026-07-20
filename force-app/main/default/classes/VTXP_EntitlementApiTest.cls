/**
 * DEPLOY TO: Partner Org
 * Covers VTXP_EntitlementApi + VTXP_EntitlementService.
 * Adjust field values below (Status__c, License_Status__c picklist values)
 * to match your actual picklist configuration.
 */
@isTest
private class VTXP_EntitlementApiTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Acme Production Account');
        insert acc;

        VTXY_SubscriberOrg__c subOrg = new VTXY_SubscriberOrg__c(
            Name = 'Acme Production',
            Account__c = acc.Id,
            OrgId__c = '00D000000000001EAA',
            License_Status__c = 'ACTIVE',
            PackageVersion__c = '0.1.0',
            Status__c = 'Active'
        );
        insert subOrg;

        VTXY_ProviderLicense__c license = new VTXY_ProviderLicense__c(
            Name = 'Acme License',
            Subscriber_Org_del__c = subOrg.Id,
            License_Type__c = 'Broadcast',
            Status__c = 'ACTIVE',
            Effective_From__c = Date.today().addDays(-30),
            Effective_To__c = Date.newInstance(2026, 12, 31),
            Provider__c = 'Telephony provider.',
            Provider_Account_Id__c = 'ACCT-TEST-0001',
            Provider_License_Id__c = 'LIC-TEST-0001'

        );
        insert license;

        insert new VTXY_FeatureEntitlement__c(
            Name = 'Softphone',
            Provider_License_del__c = license.Id,
            FeatureCode__c = 'SOFTPHONE',
            Enabled__c = true,
            LimitType__c = 'PerMonth',
            LimitValue__c = 5000
        );

        insert new VTXY_ProviderNumber__c(
            Name = 'Main Line',
            Provider_License__c = license.Id,
            Subscriber_Org__c = subOrg.Id,
            Phone_Number__c = '+14155550123',
            Status__c = 'AVAILABLE',
            Capabilities__c = '	Inbound'
        );
    }

    @isTest
    static void testSuccessfulSync() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/vtxp/v1/entitlements/sync';
        req.httpMethod = 'GET';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'subscriberOrgId' => '00D000000000001EAA',
            'subscriberOrgName' => 'Acme Production',
            'packageVersion' => '0.1.0',
            'namespace' => 'VTXY',
            'requestId' => 'REQ-000001',
            'timestamp' => '2026-07-15T10:00:00Z',
            'syncReason' => 'ADMIN_BUTTON'
        }));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        VTXP_EntitlementApi.syncPost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        VTXP_EntitlementSyncResponseDTO resp = (VTXP_EntitlementSyncResponseDTO) JSON.deserialize(
            RestContext.response.responseBody.toString(), VTXP_EntitlementSyncResponseDTO.class
        );
        System.assertEquals(true, resp.success);
        System.assertEquals('ACTIVE', resp.data.licenseStatus);
        System.assertEquals(true, resp.data.features.get('SOFTPHONE'));
        System.assertEquals(1, resp.data.providerNumbers.size());
    }

    @isTest
    static void testUnknownSubscriber() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/vtxp/v1/entitlements/sync';
        req.httpMethod = 'GET';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'subscriberOrgId' => '00DUNKNOWN0000000AAA'
        }));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        VTXP_EntitlementApi.syncPost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        VTXP_EntitlementSyncResponseDTO resp = (VTXP_EntitlementSyncResponseDTO) JSON.deserialize(
            RestContext.response.responseBody.toString(), VTXP_EntitlementSyncResponseDTO.class
        );
        System.assertEquals(false, resp.success);
        System.assertEquals('SUBSCRIBER_NOT_REGISTERED', resp.errorCode);
    }
}