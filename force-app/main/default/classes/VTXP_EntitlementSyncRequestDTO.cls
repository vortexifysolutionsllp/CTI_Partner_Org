/**
 * DEPLOY TO: Partner Org
 * Maps the inbound JSON body/params sent by the Subscriber org.
 */
public class VTXP_EntitlementSyncRequestDTO {
    public String subscriberOrgId;
    public String subscriberOrgName;
    public String packageVersion;
    public String namespace;
    public String requestId;
    public String timestamp;
    public String syncReason;
}