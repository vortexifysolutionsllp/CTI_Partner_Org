/**
 * DEPLOY TO: Partner Org
 * Exposes: /services/apexrest/vtxp/v1/entitlements/sync
 *
 * Accepts BOTH GET (per your original API table, query params or a
 * best-effort body read) and POST (the Subscriber org's client sends
 * POST with a real JSON body, which is the correct way to send a body
 * over HTTP). Both annotations delegate to the same shared logic.
 */
@RestResource(urlMapping='/vtxp/v1/entitlements/sync')
global without sharing class VTXP_EntitlementApi {

    @HttpGet
    global static void syncGet() {
        handleSync();
    }

    @HttpPost
    global static void syncPost() {
        handleSync();
    }

    private static void handleSync() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        VTXP_EntitlementSyncResponseDTO responseDto;

        try {
            VTXP_EntitlementSyncRequestDTO requestDto = parseRequest(req);
            responseDto = VTXP_EntitlementService.resolveEntitlements(requestDto);
            res.statusCode = responseDto.success ? 200 : 400;

        } catch (Exception ex) {
            responseDto = VTXP_EntitlementSyncResponseDTO.failure(
                'Unexpected error: ' + ex.getMessage(), 'INTERNAL_ERROR'
            );
            res.statusCode = 500;
        }

        res.responseBody = Blob.valueOf(JSON.serialize(responseDto, true));
    }

    private static VTXP_EntitlementSyncRequestDTO parseRequest(RestRequest req) {
        if (req.requestBody != null && req.requestBody.size() > 0) {
            return (VTXP_EntitlementSyncRequestDTO) JSON.deserialize(
                req.requestBody.toString(), VTXP_EntitlementSyncRequestDTO.class
            );
        }
        // Fallback: read as query params, e.g. ?subscriberOrgId=00Dxxxxxxxxxxxx
        VTXP_EntitlementSyncRequestDTO dto = new VTXP_EntitlementSyncRequestDTO();
        dto.subscriberOrgId   = req.params.get('subscriberOrgId');
        dto.subscriberOrgName = req.params.get('subscriberOrgName');
        dto.packageVersion    = req.params.get('packageVersion');
        dto.namespace         = req.params.get('namespace');
        dto.requestId         = req.params.get('requestId');
        dto.timestamp         = req.params.get('timestamp');
        dto.syncReason        = req.params.get('syncReason');
        return dto;
    }
}