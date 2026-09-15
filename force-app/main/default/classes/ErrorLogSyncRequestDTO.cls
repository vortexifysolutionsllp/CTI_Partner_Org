/**
 * DEPLOY TO: Partner Org
 *
 * Represents the complete payload sent by the Subscriber Org.
 *
 * Expected JSON:
 *
 * {
 *   "errorLogs": [
 *      {
 *          "id": "...",
 *          "name": "...",
 *          "className": "...",
 *          ...
 *      }
 *   ],
 *   "count": 1
 * }
 */
public class ErrorLogSyncRequestDTO {

    public List<ErrorLogWrapper> errorLogs;
    public Integer count;

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