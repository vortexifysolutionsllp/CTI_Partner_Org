public with sharing class InvoiceGeneratorController {

    public class BillingDetailsDTO {

        @AuraEnabled
        public Date billingStartDate;

        @AuraEnabled
        public Date billingEndDate;

        @AuraEnabled
        public String accountSid;

        public BillingDetailsDTO(
            Date billingStartDate,
            Date billingEndDate,
            String accountSid
        ) {
            this.billingStartDate = billingStartDate;
            this.billingEndDate = billingEndDate;
            this.accountSid = accountSid;
        }
    }

    public class InvoiceJobDTO {

        @AuraEnabled
        public String jobId;

        @AuraEnabled
        public String requestKey;

        public InvoiceJobDTO(
            String jobId,
            String requestKey
        ) {
            this.jobId = jobId;
            this.requestKey = requestKey;
        }
    }

    public class InvoiceStatusDTO {

        @AuraEnabled
        public String status;

        @AuraEnabled
        public String errorMessage;

        @AuraEnabled
        public String invoiceData;

        @AuraEnabled
        public Integer pagesRetrieved;

        public InvoiceStatusDTO() {
        }
    }


    /*
     * ============================================================
     * CALCULATE CURRENT BILLING PERIOD
     * ============================================================
     *
     * CASE 1:
     * Billing_Start_Date__c IS NULL
     *
     *     Billing Start Date = exactly one month before today
     *     Billing End Date   = today
     *
     * Example:
     *
     *     Today = 17/09/2026
     *
     *     Start = 17/08/2026
     *     End   = 17/09/2026
     *
     *
     * CASE 2:
     * Billing_Start_Date__c IS NOT NULL
     *
     *     Only the DAY of the stored date is used.
     *
     * Example:
     *
     *     Stored date = 18/07/2002
     *     Billing day = 18
     *
     *     Today = 17/09/2026
     *
     *     Start = 18/08/2026
     *     End   = 17/09/2026
     *
     *     Today = 18/09/2026
     *
     *     Start = 18/09/2026
     *     End   = 17/10/2026
     * ============================================================
     */
    private static List<Date> calculateBillingPeriod(
        Date storedBillingStartDate
    ) {

        Date today = Date.today();

        /*
         * --------------------------------------------------------
         * BILLING START DATE IS BLANK
         * --------------------------------------------------------
         *
         * Do NOT throw an error.
         *
         * Use one month before today as the start date
         * and today as the end date.
         */
        if (storedBillingStartDate == null) {

            return new List<Date>{
                today.addMonths(-1),
                today
            };
        }

        /*
         * --------------------------------------------------------
         * BILLING START DATE EXISTS
         * --------------------------------------------------------
         *
         * Only use the DAY.
         * Ignore the original year and month.
         */
        Integer billingDay =
            storedBillingStartDate.day();

        Integer billingYear =
            today.year();

        Integer billingMonth =
            today.month();

        /*
         * If today's day is before the billing day,
         * the billing period started in the previous month.
         */
        if (today.day() < billingDay) {

            billingMonth--;

            if (billingMonth == 0) {

                billingMonth = 12;
                billingYear--;
            }
        }

        /*
         * First day of billing month.
         */
        Date firstOfBillingMonth =
            Date.newInstance(
                billingYear,
                billingMonth,
                1
            );

        /*
         * Last day of billing month.
         */
        Integer lastDayOfBillingMonth =
            firstOfBillingMonth
                .addMonths(1)
                .addDays(-1)
                .day();

        /*
         * Handle billing days that don't exist
         * in a particular month.
         */
        Integer actualBillingDay =
            Math.min(
                billingDay,
                lastDayOfBillingMonth
            );

        Date billingStartDate =
            Date.newInstance(
                billingYear,
                billingMonth,
                actualBillingDay
            );

        /*
         * Determine next billing month.
         */
        Date nextBillingMonth =
            billingStartDate.addMonths(1);

        Date firstOfNextBillingMonth =
            Date.newInstance(
                nextBillingMonth.year(),
                nextBillingMonth.month(),
                1
            );

        /*
         * Last day of next billing month.
         */
        Integer lastDayOfNextBillingMonth =
            firstOfNextBillingMonth
                .addMonths(1)
                .addDays(-1)
                .day();

        /*
         * Handle billing days that don't exist
         * in the next month.
         */
        Integer actualNextBillingDay =
            Math.min(
                billingDay,
                lastDayOfNextBillingMonth
            );

        Date nextBillingDate =
            Date.newInstance(
                nextBillingMonth.year(),
                nextBillingMonth.month(),
                actualNextBillingDay
            );

        /*
         * Billing ends one day before the next
         * billing anniversary.
         */
        Date billingEndDate =
            nextBillingDate.addDays(-1);

        return new List<Date>{
            billingStartDate,
            billingEndDate
        };
    }


    /*
     * ============================================================
     * GET BILLING DETAILS
     * ============================================================
     */
    @AuraEnabled(cacheable=true)
    public static BillingDetailsDTO getBillingDetails(
        Id subscriberOrgId
    ) {

        if (subscriberOrgId == null) {

            throw new AuraHandledException(
                'Subscriber Org Id is required.'
            );
        }

        VTXY_SubscriberOrg__c subscriberOrg = [
            SELECT
                Id,
                Billing_Start_Date__c,
                Account_SID__c
            FROM VTXY_SubscriberOrg__c
            WHERE Id = :subscriberOrgId
            LIMIT 1
        ];

        if (
            String.isBlank(
                subscriberOrg.Account_SID__c
            )
        ) {

            throw new AuraHandledException(
                'Account SID is not configured.'
            );
        }

        /*
         * calculateBillingPeriod() handles both:
         *
         * Billing_Start_Date__c populated
         * Billing_Start_Date__c blank
         */
        List<Date> billingPeriod =
            calculateBillingPeriod(
                subscriberOrg.Billing_Start_Date__c
            );

        return new BillingDetailsDTO(
            billingPeriod[0],
            billingPeriod[1],
            subscriberOrg.Account_SID__c
        );
    }


    /*
     * ============================================================
     * GENERATE INVOICE
     * ============================================================
     */
    @AuraEnabled
public static InvoiceJobDTO generateInvoice(
    Id subscriberOrgId,
    Date billingStartDate,
    Date billingEndDate
) {

    if (subscriberOrgId == null) {

        throw new AuraHandledException(
            'Subscriber Org Id is required.'
        );
    }

    /*
     * Billing dates come from the LWC.
     *
     * The LWC initially receives automatically calculated
     * dates from getBillingDetails(), but the user can edit
     * them before generating the invoice.
     */
    if (billingStartDate == null) {

        throw new AuraHandledException(
            'Billing Start Date is required.'
        );
    }

    if (billingEndDate == null) {

        throw new AuraHandledException(
            'Billing End Date is required.'
        );
    }

    if (billingStartDate > billingEndDate) {

        throw new AuraHandledException(
            'Billing Start Date cannot be later than Billing End Date.'
        );
    }

    VTXY_SubscriberOrg__c subscriberOrg = [
        SELECT
            Id,
            Billing_Start_Date__c,
            Account_SID__c
        FROM VTXY_SubscriberOrg__c
        WHERE Id = :subscriberOrgId
        LIMIT 1
    ];

    if (
        String.isBlank(
            subscriberOrg.Account_SID__c
        )
    ) {

        throw new AuraHandledException(
            'Twilio Account SID is not configured.'
        );
    }

    /*
     * Use the dates selected by the user.
     */
    Date startDate = billingStartDate;
    Date endDate = billingEndDate;

    /*
     * Unique identifier for the complete
     * invoice processing operation.
     */
    String requestKey =
    'INV' +
    String.valueOf(Crypto.getRandomLong()) +
    String.valueOf(Datetime.now().getTime());

requestKey = requestKey.replaceAll('[^a-zA-Z0-9]', '');

    /*
     * Store initial status.
     */
    Map<String, Object> meta =
        new Map<String, Object>();

    meta.put(
        'status',
        'QUEUED'
    );

    meta.put(
        'subscriberOrgId',
        String.valueOf(
            subscriberOrgId
        )
    );

    meta.put(
        'billingStartDate',
        String.valueOf(
            startDate
        )
    );

    meta.put(
        'billingEndDate',
        String.valueOf(
            endDate
        )
    );

    meta.put(
        'accountSid',
        subscriberOrg.Account_SID__c
    );

    meta.put(
        'pagesRetrieved',
        0
    );

    InvoiceCacheService.storeMeta(
        requestKey,
        JSON.serialize(meta)
    );

    /*
     * First Queueable.
     */
    InvoiceGenerationQueueable job =
        new InvoiceGenerationQueueable(
            subscriberOrg.Id,
            startDate,
            endDate,
            subscriberOrg.Account_SID__c,
            requestKey
        );

    Id jobId =
        System.enqueueJob(job);

    return new InvoiceJobDTO(
        String.valueOf(jobId),
        requestKey
    );
}


    /*
     * ============================================================
     * GET INVOICE STATUS
     * ============================================================
     */
    @AuraEnabled
    public static InvoiceStatusDTO getInvoiceStatus(
        String requestKey
    ) {

        if (String.isBlank(requestKey)) {

            throw new AuraHandledException(
                'Request Key is required.'
            );
        }

        InvoiceStatusDTO result =
            new InvoiceStatusDTO();

        String cachedMeta =
            InvoiceCacheService.getMeta(
                requestKey
            );

        if (String.isBlank(cachedMeta)) {

            result.status =
                'EXPIRED';

            result.errorMessage =
                'Invoice processing data has expired from Platform Cache.';

            return result;
        }

        Map<String, Object> meta =
            (Map<String, Object>)
            JSON.deserializeUntyped(
                cachedMeta
            );

        result.status =
            (String)
            meta.get('status');

        result.errorMessage =
            (String)
            meta.get('errorMessage');

        Object pageCount =
            meta.get('pagesRetrieved');

        if (pageCount != null) {

            result.pagesRetrieved =
                Integer.valueOf(
                    String.valueOf(
                        pageCount
                    )
                );
        }

        /*
         * Don't return all pages from this method.
         *
         * LWC retrieves pages separately.
         */
        if (
            result.status ==
            'COMPLETED'
        ) {

            result.invoiceData =
                JSON.serialize(meta);
        }

        return result;
    }


    /*
     * ============================================================
     * GET INVOICE PAGE
     * ============================================================
     */
    @AuraEnabled(cacheable=true)
    public static String getInvoicePage(
        String requestKey,
        Integer pageNumber
    ) {

        if (String.isBlank(requestKey)) {

            throw new AuraHandledException(
                'Request Key is required.'
            );
        }

        if (
            pageNumber == null ||
            pageNumber <= 0
        ) {

            throw new AuraHandledException(
                'Invalid page number.'
            );
        }

        String pageData =
            InvoiceCacheService.getPage(
                requestKey,
                pageNumber
            );

        if (String.isBlank(pageData)) {

            throw new AuraHandledException(
                'Invoice page data was not found.'
            );
        }

        return pageData;
    }

@AuraEnabled
public static String createInvoicePdfPage(
    String html
) {
    if (String.isBlank(html)) {
        throw new AuraHandledException(
            'Invoice page HTML is required.'
        );
    }

    return InvoicePdfApiService.createPdfFromHtml(
        html
    );
}
@AuraEnabled
public static String getPdfJobStatus(
    String jobId
) {
    if (String.isBlank(jobId)) {
        throw new AuraHandledException(
            'PDF job ID is required.'
        );
    }

    InvoicePdfApiService.JobStatusResponse response =
        InvoicePdfApiService.checkJob(jobId);

    return JSON.serialize(response);
}
@AuraEnabled
public static String mergeInvoicePdfs(
    List<String> pdfUrls
) {
    if (pdfUrls == null ||
        pdfUrls.isEmpty()) {

        throw new AuraHandledException(
            'No PDF pages were provided.'
        );
    }

    InvoicePdfApiService.MergeResponse response =
        InvoicePdfApiService.mergePdfs(
            pdfUrls
        );

    return JSON.serialize(response);
}
@AuraEnabled
public static String saveMergedInvoice(
    Id subscriberOrgId, String requestKey, String mergedPdfUrl
) {
    if (subscriberOrgId == null) {
        throw new AuraHandledException('Subscriber Org Id is required.');
    }
    if (String.isBlank(mergedPdfUrl)) {
        throw new AuraHandledException('Merged PDF URL is required.');
    }

    String fileName = 'Invoice-' + requestKey + '.pdf';
    Integer pagesRetrieved = 0;

    String cachedMeta = InvoiceCacheService.getMeta(requestKey);
    if (!String.isBlank(cachedMeta)) {
        Map<String, Object> meta =
            (Map<String, Object>) JSON.deserializeUntyped(cachedMeta);

        String startStr = (String) meta.get('billingStartDate');
        String endStr   = (String) meta.get('billingEndDate');

        if (!String.isBlank(startStr) && !String.isBlank(endStr)) {
            VTXY_SubscriberOrg__c subOrg = [
                SELECT Name FROM VTXY_SubscriberOrg__c
                WHERE Id = :subscriberOrgId LIMIT 1
            ];
            String safeName = subOrg.Name.replaceAll('[^a-zA-Z0-9 _-]', '');
            fileName = 'Invoice - ' + safeName + ' - ' + startStr + ' to ' + endStr + '.pdf';
        }

        Object pc = meta.get('pagesRetrieved');
        if (pc != null) {
            pagesRetrieved = Integer.valueOf(String.valueOf(pc));
        }
    }

    Blob pdfBlob = InvoicePdfApiService.downloadPdf(mergedPdfUrl);
    Id docId = InvoicePdfApiService.saveAsSalesforceFile(subscriberOrgId, fileName, pdfBlob);

    // Cache cleanup (must never fail the save)
    try {
        for (Integer p = 1; p <= pagesRetrieved; p++) {
            InvoiceCacheService.removePage(requestKey, p);
        }
        InvoiceCacheService.removeMeta(requestKey);
    } catch (Exception ex) {
        System.debug(LoggingLevel.WARN, 'Cache cleanup failed: ' + ex.getMessage());
    }

    return String.valueOf(docId);
}
}