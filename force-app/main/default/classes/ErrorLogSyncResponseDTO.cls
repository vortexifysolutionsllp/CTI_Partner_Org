/**
 * DEPLOY TO: Partner Org
 *
 * Response returned to Subscriber Org after processing
 * one or more Error Logs.
 */
public class ErrorLogSyncResponseDTO {

    public Boolean success;
    public String status;
    public Integer count;
    public List<ErrorLogResult> results;

    public class ErrorLogResult {

        public String requestId;
        public String errorLogId;

        public String status;
        public String caseId;

        public String message;
        public String errorCode;
    }

    public static ErrorLogSyncResponseDTO success(
        List<ErrorLogResult> results
    ) {

        ErrorLogSyncResponseDTO response =
            new ErrorLogSyncResponseDTO();

        response.success = true;
        response.status = 'SYNCED';
        response.count = results == null ? 0 : results.size();
        response.results = results;

        return response;
    }

    public static ErrorLogSyncResponseDTO failure(
        String message,
        String errorCode
    ) {

        ErrorLogSyncResponseDTO response =
            new ErrorLogSyncResponseDTO();

        response.success = false;
        response.status = 'FAILED';
        response.count = 0;
        response.results = new List<ErrorLogResult>();

        ErrorLogResult result = new ErrorLogResult();
        result.status = 'FAILED';
        result.message = message;
        result.errorCode = errorCode;

        response.results.add(result);

        return response;
    }
}