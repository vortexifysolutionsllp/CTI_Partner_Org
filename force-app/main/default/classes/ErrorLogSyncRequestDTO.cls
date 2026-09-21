public class ErrorLogSyncRequestDTO {

    /*
     * ============================================================
     * ERROR LOGS
     * ============================================================
     */

    public List<ErrorLogWrapper> errorLogs;

    public Integer count;

    public String subscriberOrgId;

    public String status;

    public String assignedPhoneNumbers;

    public Decimal currentBalance;



    /*
     * ============================================================
     * SUBSCRIBER USAGE WRAPPER
     * ============================================================
     */

    // public class SubscriberUsageWrapper {

    //     public String subscriberOrgId;

    //     public String status;

    //     public String assignedPhoneNumbers;

    //     public Decimal currentBalance;

    //     public String errorLogId;
    // }


    /*
     * ============================================================
     * ERROR LOG WRAPPER
     * ============================================================
     */

    public class ErrorLogWrapper {

        public String id;

        public String name;

        public String className;

        public String methodName;

        public String component;

        public String logLevel;

        public String status;

        public String message;

        public String stackTrace;

        public String payloadJSON;

        public String contextJSON;

        public String relatedRecordId;

        public String errorCode;

        public String correlationId;

        public Datetime createdDate;
    }
}