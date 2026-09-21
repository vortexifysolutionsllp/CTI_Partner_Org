public without sharing class InvoiceGenerationQueueable
    implements Queueable, Database.AllowsCallouts {

    private Id subscriberOrgId;
    private Date billingStartDate;
    private Date billingEndDate;
    private String accountSid;

    /*
     * Root job identifies the complete invoice operation.
     * Every chained Queueable uses the same rootJobId.
     */
    private String rootJobId;

    /*
     * Which Twilio page this Queueable represents.
     */
    private Integer pageNumber;

    /*
     * Twilio next_page_uri.
     * Null for the first page.
     */
    private String nextPageUri;


    /*
     * ------------------------------------------------------------
     * FIRST QUEUEABLE
     * ------------------------------------------------------------
     */
    public InvoiceGenerationQueueable(
        Id subscriberOrgId,
        Date billingStartDate,
        Date billingEndDate,
        String accountSid,
        String rootJobId
    ) {
        this.subscriberOrgId = subscriberOrgId;
        this.billingStartDate = billingStartDate;
        this.billingEndDate = billingEndDate;
        this.accountSid = accountSid;
        this.rootJobId = rootJobId;

        this.pageNumber = 1;
        this.nextPageUri = null;
    }


    /*
     * ------------------------------------------------------------
     * CHAINED QUEUEABLE
     * ------------------------------------------------------------
     */
    public InvoiceGenerationQueueable(
        Id subscriberOrgId,
        Date billingStartDate,
        Date billingEndDate,
        String accountSid,
        String rootJobId,
        Integer pageNumber,
        String nextPageUri
    ) {
        this.subscriberOrgId = subscriberOrgId;
        this.billingStartDate = billingStartDate;
        this.billingEndDate = billingEndDate;
        this.accountSid = accountSid;
        this.rootJobId = rootJobId;

        this.pageNumber = pageNumber;
        this.nextPageUri = nextPageUri;
    }


    /*
     * ------------------------------------------------------------
     * EXECUTE
     * ------------------------------------------------------------
     */
    public void execute(
        QueueableContext context
    ) {

        try {

            System.debug(
                LoggingLevel.INFO,
                '================================================'
            );

            System.debug(
                LoggingLevel.INFO,
                'INVOICE QUEUEABLE START'
            );

            System.debug(
                LoggingLevel.INFO,
                'Root Job ID: ' + rootJobId
            );

            System.debug(
                LoggingLevel.INFO,
                'Page Number: ' + pageNumber
            );

            System.debug(
                LoggingLevel.INFO,
                'Billing Start Date: ' + billingStartDate
            );

            System.debug(
                LoggingLevel.INFO,
                'Billing End Date: ' + billingEndDate
            );


            /*
             * ----------------------------------------------------
             * CALL ONE TWILIO PAGE
             * ----------------------------------------------------
             */
            TwilioCallLogService.FetchResult result =
                TwilioCallLogService.fetchCalls(
                    accountSid,
                    billingStartDate,
                    billingEndDate,
                    nextPageUri
                );


            if (result == null) {

                throw new CalloutException(
                    'Twilio returned an empty response.'
                );
            }


            System.debug(
                LoggingLevel.INFO,
                'Twilio calls returned: ' +
                result.calls.size()
            );

            System.debug(
                LoggingLevel.INFO,
                'Next Page URI exists: ' +
                !String.isBlank(result.nextPageUri)
            );


            /*
             * ----------------------------------------------------
             * BUILD PAGE PAYLOAD
             * ----------------------------------------------------
             */
            Map<String, Object> pagePayload =
                new Map<String, Object>();

            pagePayload.put(
                'pageNumber',
                pageNumber
            );

            pagePayload.put(
                'calls',
                result.calls
            );


            String serializedPage =
                JSON.serialize(pagePayload);


            System.debug(
                LoggingLevel.INFO,
                'Serialized page length: ' +
                serializedPage.length()
            );


            /*
             * ----------------------------------------------------
             * STORE PAGE
             * ----------------------------------------------------
             */
            System.debug(
                LoggingLevel.INFO,
                'BEFORE CACHE PAGE PUT - ' +
                'Root=' + rootJobId +
                ', Page=' + pageNumber +
                ', Length=' + serializedPage.length()
            );


            InvoiceCacheService.storePage(
                rootJobId,
                pageNumber,
                serializedPage
            );


            System.debug(
                LoggingLevel.INFO,
                'CACHE PAGE PUT COMPLETED'
            );


            /*
             * ----------------------------------------------------
             * VERIFY PAGE IMMEDIATELY
             * ----------------------------------------------------
             *
             * This is intentionally done inside the same
             * Queueable transaction.
             */
            String cachedPage =
                InvoiceCacheService.getPage(
                    rootJobId,
                    pageNumber
                );


            if (cachedPage == null) {

                System.debug(
                    LoggingLevel.ERROR,
                    'AFTER CACHE PAGE PUT - CACHE = NULL'
                );

            } else {

                System.debug(
                    LoggingLevel.INFO,
                    'AFTER CACHE PAGE PUT - ' +
                    'CACHE = FOUND, LENGTH=' +
                    cachedPage.length()
                );
            }


            /*
             * ----------------------------------------------------
             * MORE PAGES?
             * ----------------------------------------------------
             */
            if (
                !String.isBlank(
                    result.nextPageUri
                )
            ) {

                /*
                 * ------------------------------------------------
                 * UPDATE PROCESSING META
                 * ------------------------------------------------
                 */
                Map<String, Object> meta =
                    new Map<String, Object>();

                meta.put(
                    'status',
                    'PROCESSING'
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
                        billingStartDate
                    )
                );

                meta.put(
                    'billingEndDate',
                    String.valueOf(
                        billingEndDate
                    )
                );

                meta.put(
                    'accountSid',
                    accountSid
                );

                meta.put(
                    'pagesRetrieved',
                    pageNumber
                );


                String serializedMeta =
                    JSON.serialize(meta);


                /*
                 * ------------------------------------------------
                 * STORE META
                 * ------------------------------------------------
                 */
                System.debug(
                    LoggingLevel.INFO,
                    'BEFORE CACHE META PUT - ' +
                    'Root=' + rootJobId
                );


                InvoiceCacheService.storeMeta(
                    rootJobId,
                    serializedMeta
                );


                System.debug(
                    LoggingLevel.INFO,
                    'CACHE META PUT COMPLETED'
                );


                /*
                 * ------------------------------------------------
                 * VERIFY META IMMEDIATELY
                 * ------------------------------------------------
                 */
                String cachedMeta =
                    InvoiceCacheService.getMeta(
                        rootJobId
                    );


                if (cachedMeta == null) {

                    System.debug(
                        LoggingLevel.ERROR,
                        'AFTER CACHE META PUT - CACHE = NULL'
                    );

                } else {

                    System.debug(
                        LoggingLevel.INFO,
                        'AFTER CACHE META PUT - ' +
                        'CACHE = FOUND, LENGTH=' +
                        cachedMeta.length()
                    );
                }


                /*
                 * ------------------------------------------------
                 * ENQUEUE NEXT PAGE
                 * ------------------------------------------------
                 */
                InvoiceGenerationQueueable nextJob =
                    new InvoiceGenerationQueueable(
                        subscriberOrgId,
                        billingStartDate,
                        billingEndDate,
                        accountSid,
                        rootJobId,
                        pageNumber + 1,
                        result.nextPageUri
                    );


                Id nextJobId =
                    System.enqueueJob(
                        nextJob
                    );


                System.debug(
                    LoggingLevel.INFO,
                    'NEXT QUEUEABLE ENQUEUED - ' +
                    'JobId=' + nextJobId +
                    ', NextPage=' + (pageNumber + 1)
                );

            } else {

                /*
                 * ------------------------------------------------
                 * NO MORE PAGES
                 * ------------------------------------------------
                 */
                Map<String, Object> meta =
                    new Map<String, Object>();

                meta.put(
                    'status',
                    'COMPLETED'
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
                        billingStartDate
                    )
                );

                meta.put(
                    'billingEndDate',
                    String.valueOf(
                        billingEndDate
                    )
                );

                meta.put(
                    'accountSid',
                    accountSid
                );

                meta.put(
                    'pagesRetrieved',
                    pageNumber
                );

                meta.put(
                    'completed',
                    true
                );


                String serializedMeta =
                    JSON.serialize(meta);


                /*
                 * ------------------------------------------------
                 * STORE COMPLETED META
                 * ------------------------------------------------
                 */
                System.debug(
                    LoggingLevel.INFO,
                    'BEFORE FINAL META PUT - ' +
                    'Root=' + rootJobId
                );


                InvoiceCacheService.storeMeta(
                    rootJobId,
                    serializedMeta
                );


                System.debug(
                    LoggingLevel.INFO,
                    'FINAL CACHE META PUT COMPLETED'
                );


                /*
                 * ------------------------------------------------
                 * VERIFY FINAL META
                 * ------------------------------------------------
                 */
                String finalCachedMeta =
                    InvoiceCacheService.getMeta(
                        rootJobId
                    );


                if (finalCachedMeta == null) {

                    System.debug(
                        LoggingLevel.ERROR,
                        'FINAL META CACHE = NULL'
                    );

                } else {

                    System.debug(
                        LoggingLevel.INFO,
                        'FINAL META CACHE = FOUND, ' +
                        'LENGTH=' +
                        finalCachedMeta.length()
                    );
                }


                System.debug(
                    LoggingLevel.INFO,
                    'INVOICE RETRIEVAL COMPLETED - ' +
                    'Total Pages=' + pageNumber
                );
            }


            System.debug(
                LoggingLevel.INFO,
                'INVOICE QUEUEABLE END - ' +
                'Root=' + rootJobId +
                ', Page=' + pageNumber
            );


        } catch (Exception e) {

            /*
             * ----------------------------------------------------
             * FAILURE
             * ----------------------------------------------------
             */
            Map<String, Object> meta =
                new Map<String, Object>();

            meta.put(
                'status',
                'FAILED'
            );

            meta.put(
                'errorMessage',
                e.getMessage()
            );

            meta.put(
                'pageNumber',
                pageNumber
            );


            try {

                InvoiceCacheService.storeMeta(
                    rootJobId,
                    JSON.serialize(meta)
                );

                System.debug(
                    LoggingLevel.ERROR,
                    'FAILURE META STORED'
                );

            } catch (Exception cacheException) {

                System.debug(
                    LoggingLevel.ERROR,
                    'FAILED TO STORE FAILURE META: ' +
                    cacheException.getMessage()
                );
            }


            System.debug(
                LoggingLevel.ERROR,
                'Invoice Queueable failed. ' +
                'Root Job: ' +
                rootJobId +
                ', Page: ' +
                pageNumber +
                ', Error: ' +
                e.getStackTraceString()
            );


            throw e;
        }
    }
}