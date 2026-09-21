/*
 * DEPLOY TO: Partner Org
 *
 * Response returned to Subscriber Org after processing
 * Error Logs and Subscriber Org information.
 */
public class ErrorLogSyncResponseDTO {

    public Boolean success;
    public String status;
    public Integer count;

    /*
     * Subscriber Org information
     */
    public String subscriberOrgId;
    public String subscriberOrgRecordId;
    public String subscriberOrgStatus;

    /*
     * Balance information
     */
    public Decimal previousBalance;
    public Decimal currentBalance;

    /*
     * Final phone numbers stored on Subscriber Org
     */
    public List<String> assignedPhoneNumbers;

    /*
     * Phone number change information
     */
    public PhoneNumberChange phoneNumberChanges;

    /*
     * Error Log results
     */
    public List<ErrorLogResult> results;


    /*
     * ============================================================
     * PHONE NUMBER CHANGE RESPONSE
     * ============================================================
     */
    public class PhoneNumberChange {

        public String action;

        public List<String> added;

        public List<String> removed;

        public PhoneNumberChange() {

            added = new List<String>();
            removed = new List<String>();
        }
    }


    /*
     * ============================================================
     * ERROR LOG RESULT
     * ============================================================
     */
    public class ErrorLogResult {

        public String requestId;
        public String errorLogId;
        public String status;
        public String caseId;
        public String message;
        public String errorCode;
    }


    /*
     * ============================================================
     * SUCCESS RESPONSE
     * ============================================================
     */
    public static ErrorLogSyncResponseDTO success(
        List<ErrorLogResult> results
    ) {

        ErrorLogSyncResponseDTO response =
            new ErrorLogSyncResponseDTO();

        response.success = true;
        response.status = 'SYNCED';

        response.count =
            results == null
                ? 0
                : results.size();

        response.results = results;

        return response;
    }


    /*
     * ============================================================
     * FAILURE RESPONSE
     * ============================================================
     */
    public static ErrorLogSyncResponseDTO failure(
        String message,
        String errorCode
    ) {

        ErrorLogSyncResponseDTO response =
            new ErrorLogSyncResponseDTO();

        response.success = false;
        response.status = 'FAILED';
        response.count = 0;

        response.results =
            new List<ErrorLogResult>();

        ErrorLogResult result =
            new ErrorLogResult();

        result.status = 'FAILED';
        result.message = message;
        result.errorCode = errorCode;

        response.results.add(result);

        return response;
    }
}