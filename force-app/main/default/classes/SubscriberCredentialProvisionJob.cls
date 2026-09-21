/*
 * DEPLOY TO: Partner Org
 *
 * Runs SubscriberCredentialProvisioner outside the transaction that
 * inserts VTXY_SubscriberOrg__c. Creating a Named/External Credential
 * is a setup-metadata operation; doing it in the same transaction as a
 * standard sObject DML (the insert in syncSubscriberOrg) risks a mixed
 * DML error, so it's deferred to its own queued execution instead -
 * same pattern the subscriber org uses for SubscriberOrgSyncJob.
 */
public with sharing class SubscriberCredentialProvisionJob implements Queueable {

    private String subscriberOrgId;
    private String subscriberOrgName;
    private String calloutUrl;

    public SubscriberCredentialProvisionJob(String subscriberOrgId, String subscriberOrgName,String calloutUrl) {
        this.subscriberOrgId = subscriberOrgId;
        this.subscriberOrgName = subscriberOrgName;
        this.calloutUrl=calloutUrl;
    }

    public void execute(QueueableContext ctx) {
        
            String developerName = SubscriberCredentialProvisionerClass.buildDeveloperName(subscriberOrgId, subscriberOrgName );
            SubscriberCredentialProvisionerClass.provision(developerName, subscriberOrgId, subscriberOrgName, calloutUrl);
    }
}