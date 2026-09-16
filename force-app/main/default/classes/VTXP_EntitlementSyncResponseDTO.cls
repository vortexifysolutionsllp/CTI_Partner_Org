/**
 * DEPLOY TO: Partner Org
 * Shape matches your Sample Success/Failure Response JSON exactly.
 */
public class VTXP_EntitlementSyncResponseDTO {

    public Boolean success;
    public String message;
    public DataWrapper data;
    public String errorCode;

    public class DataWrapper {
        public String licenseStatus;
        public String planCode;
        public String expiresOn;                          // yyyy-MM-dd
        public Map<String, Boolean> features;
        public LimitsWrapper limits;
        public List<ProviderNumberWrapper> providerNumbers;
    }

    public class LimitsWrapper {
        public Integer monthlyMinutes;
        public Integer maxUsers;
    }

    public class ProviderNumberWrapper {
        public String e164Number;
        public String provider;
        public String status;
        public Map<String, Boolean> capabilities;
    }

    /** Convenience builder for every failure path (not found, inactive, bad input, etc.) */
    public static VTXP_EntitlementSyncResponseDTO failure(String message, String errorCode) {
        VTXP_EntitlementSyncResponseDTO resp = new VTXP_EntitlementSyncResponseDTO();
        resp.success = false;
        resp.message = message;
        resp.data = null;
        resp.errorCode = errorCode;
        return resp;
    }
}