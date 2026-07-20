/**
 * DEPLOY TO: Partner Org
 * All the object-lookup / business logic lives here so VTXP_EntitlementApi
 * stays a thin HTTP wrapper (easier to unit test this class directly).
 */
public with sharing class VTXP_EntitlementService {

    public static VTXP_EntitlementSyncResponseDTO resolveEntitlements(VTXP_EntitlementSyncRequestDTO req) {

        if (req == null || String.isBlank(req.subscriberOrgId)) {
            return VTXP_EntitlementSyncResponseDTO.failure('Missing subscriberOrgId', 'INVALID_REQUEST');
        }

        // 1. Find the calling org by its 18-char Org Id (External Id field)
        List<VTXY_SubscriberOrg__c> subs = [
            SELECT Id, OrgId__c, Name, License_Status__c, PackageVersion__c, Status__c
            FROM VTXY_SubscriberOrg__c
            WHERE OrgId__c = :req.subscriberOrgId
            LIMIT 1
        ];

        if (subs.isEmpty()) {
            return VTXP_EntitlementSyncResponseDTO.failure('Subscriber org not found', 'SUBSCRIBER_NOT_REGISTERED');
        }
        VTXY_SubscriberOrg__c subOrg = subs[0];

        // TODO: adjust these picklist values to match your actual Status__c values
        if (subOrg.Status__c == 'Suspended' || subOrg.Status__c == 'Inactive') {
            return VTXP_EntitlementSyncResponseDTO.failure('Subscriber org is not active', 'SUBSCRIBER_INACTIVE');
        }

        // 2. Get the most relevant Provider License tied to this subscriber
        List<VTXY_ProviderLicense__c> licenses = [
            SELECT Id, License_Type__c, Status__c, Effective_From__c, Effective_To__c, Provider__c
            FROM VTXY_ProviderLicense__c
            WHERE Subscriber_Org_del__c = :subOrg.Id
            ORDER BY Effective_From__c DESC
            LIMIT 1
        ];

        VTXP_EntitlementSyncResponseDTO resp = new VTXP_EntitlementSyncResponseDTO();
        resp.success = true;
        resp.message = 'Sync resolved';
        resp.errorCode = null;

        VTXP_EntitlementSyncResponseDTO.DataWrapper data = new VTXP_EntitlementSyncResponseDTO.DataWrapper();
        data.licenseStatus = subOrg.License_Status__c;
        data.planCode      = licenses.isEmpty() ? null : licenses[0].License_Type__c;
        data.expiresOn     = (!licenses.isEmpty() && licenses[0].Effective_To__c != null)
                                ? String.valueOf(licenses[0].Effective_To__c)
                                : null;
        data.features         = new Map<String, Boolean>();
        data.limits            = new VTXP_EntitlementSyncResponseDTO.LimitsWrapper();
        data.providerNumbers  = new List<VTXP_EntitlementSyncResponseDTO.ProviderNumberWrapper>();

        if (!licenses.isEmpty()) {
            Id licenseId = licenses[0].Id;

            // 3. Feature Entitlement -> features map + limits
            for (VTXY_FeatureEntitlement__c fe : [
                SELECT FeatureCode__c, Enabled__c, LimitType__c, LimitValue__c
                FROM VTXY_FeatureEntitlement__c
                WHERE Provider_License_del__c = :licenseId
            ]) {
                if (String.isNotBlank(fe.FeatureCode__c)) {
                    data.features.put(fe.FeatureCode__c, fe.Enabled__c);
                }
                // TODO: confirm your actual LimitType__c picklist values
                if (fe.LimitValue__c != null && fe.LimitType__c == 'PerMonth') {
                    data.limits.monthlyMinutes = Integer.valueOf(fe.LimitValue__c);
                } else if (fe.LimitValue__c != null && fe.LimitType__c == 'MAX_USERS') {
                    data.limits.maxUsers = Integer.valueOf(fe.LimitValue__c);
                }
            }

            // 4. Provider Number -> providerNumbers array
            for (VTXY_ProviderNumber__c pn : [
                SELECT Phone_Number__c, Status__c, Capabilities__c
                FROM VTXY_ProviderNumber__c
                WHERE Provider_License__c = :licenseId
            ]) {
                VTXP_EntitlementSyncResponseDTO.ProviderNumberWrapper pw =
                    new VTXP_EntitlementSyncResponseDTO.ProviderNumberWrapper();
                pw.e164Number = pn.Phone_Number__c;
                pw.provider   = licenses[0].Provider__c;
                pw.status     = pn.Status__c;
                pw.capabilities = new Map<String, Boolean>();
                if (String.isNotBlank(pn.Capabilities__c)) {
                    for (String cap : pn.Capabilities__c.split(';')) {
                        pw.capabilities.put(cap.trim(), true);
                    }
                }
                data.providerNumbers.add(pw);
            }
        }

        resp.data = data;
        return resp;
    }
}