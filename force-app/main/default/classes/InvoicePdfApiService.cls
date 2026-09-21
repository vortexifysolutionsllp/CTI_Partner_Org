public with sharing class InvoicePdfApiService {

    // Named Credential #1 -> URL: https://apdf.io/api   (has the Bearer token)
    private static final String APDF_ENDPOINT   = 'callout:aPDF_API';
    private static final String CREATE_PDF_PATH = '/pdf/file/create';
    private static final String MERGE_PDF_PATH  = '/pdf/file/merge';
    private static final String JOB_STATUS_PATH = '/job/status/check';

    // Named Credential #2 -> URL: https://apdf-files.s3.eu-central-1.amazonaws.com
    // (No authentication). Used instead of a Remote Site Setting for the PDF download.
    private static final String S3_BASE_URL   = 'https://apdf-files.s3.eu-central-1.amazonaws.com';
    private static final String S3_CREDENTIAL = 'callout:aPDF_S3';

    /* ============================================================
     * DTOs
     * ============================================================ */

    public class CreatePdfResponse {
        public String job_id;
    }

    public class JobStatusResponse {
        public String id;
        public String status;
        public String error;
        public PdfResult result;
    }

    public class PdfResult {
        public String file;
        public String expiration;
        public Integer pages;
        public Integer size;
    }

    public class MergeResponse {
        public String file;
        public String expiration;
        public Integer pages;
        public Integer size;
    }

    /* ============================================================
     * Helpers
     * ============================================================ */

    // AuraHandledException.getMessage() returns "Script-thrown exception"
    // (in Apex/tests/Execute Anonymous) unless setMessage() is called.
    private static AuraHandledException buildError(String msg) {
        AuraHandledException ex = new AuraHandledException(msg);
        ex.setMessage(msg);
        return ex;
    }

    private static HttpRequest buildPost(String path, String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(APDF_ENDPOINT + path);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);
        req.setBody(body);
        return req;
    }

    private static Boolean isSuccess(HttpResponse res) {
        return res.getStatusCode() >= 200 && res.getStatusCode() < 300;
    }

    /* ============================================================
     * CREATE PDF (async -> returns job_id)
     * ============================================================ */

    public static String createPdfFromHtml(String html) {

        if (String.isBlank(html)) {
            throw buildError('Invoice HTML cannot be empty.');
        }

        String body =
            'html=' + EncodingUtil.urlEncode(html, 'UTF-8') +
            '&format=a4' +
            '&unit=mm' +
            '&orientation=landscape' +
            '&margin_top=8' +
            '&margin_right=8' +
            '&margin_bottom=8' +
            '&margin_left=8';

        HttpResponse res = new Http().send(buildPost(CREATE_PDF_PATH, body));

        if (!isSuccess(res)) {
            throw buildError(
                'aPDF Create PDF failed. HTTP ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        CreatePdfResponse response =
            (CreatePdfResponse) JSON.deserialize(res.getBody(), CreatePdfResponse.class);

        if (response == null || String.isBlank(response.job_id)) {
            throw buildError('aPDF did not return a PDF job ID. Response: ' + res.getBody());
        }

        return response.job_id;
    }

    /* ============================================================
     * CHECK PDF JOB
     * ============================================================ */

    public static JobStatusResponse checkJob(String jobId) {

        if (String.isBlank(jobId)) {
            throw buildError('aPDF job ID is required.');
        }

        String body = 'id=' + EncodingUtil.urlEncode(jobId, 'UTF-8');

        HttpResponse res = new Http().send(buildPost(JOB_STATUS_PATH, body));

        if (!isSuccess(res)) {
            throw buildError(
                'aPDF job status failed. HTTP ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        return (JobStatusResponse) JSON.deserialize(res.getBody(), JobStatusResponse.class);
    }

    /* ============================================================
     * MERGE PDFS (aPDF fetches the URLs itself; no S3 callout from Salesforce)
     * ============================================================ */

    public static MergeResponse mergePdfs(List<String> pdfUrls) {

        if (pdfUrls == null || pdfUrls.isEmpty()) {
            throw buildError('At least one PDF is required for merging.');
        }

        List<String> bodyParts = new List<String>();
        for (Integer i = 0; i < pdfUrls.size(); i++) {
            bodyParts.add(
                'files[' + i + '][file]=' + EncodingUtil.urlEncode(pdfUrls[i], 'UTF-8')
            );
        }

        HttpResponse res =
            new Http().send(buildPost(MERGE_PDF_PATH, String.join(bodyParts, '&')));

        if (!isSuccess(res)) {
            throw buildError(
                'aPDF Merge PDF failed. HTTP ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        MergeResponse response =
            (MergeResponse) JSON.deserialize(res.getBody(), MergeResponse.class);

        if (response == null || String.isBlank(response.file)) {
            throw buildError('aPDF did not return the merged PDF URL. Response: ' + res.getBody());
        }

        return response;
    }

    /* ============================================================
     * DOWNLOAD FINAL PDF
     * Goes through the aPDF_S3 Named Credential, so no Remote Site
     * Setting is needed.
     * ============================================================ */

    public static Blob downloadPdf(String pdfUrl) {

        if (String.isBlank(pdfUrl)) {
            throw buildError('PDF URL is required.');
        }

        if (!pdfUrl.startsWith(S3_BASE_URL)) {
            throw buildError(
                'PDF host is not covered by the aPDF_S3 Named Credential. URL: ' + pdfUrl
            );
        }

        // Keep path AND query string (signed links carry their signature there)
        String endpoint = S3_CREDENTIAL + pdfUrl.substring(S3_BASE_URL.length());

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);

        if (!isSuccess(res)) {
            throw buildError('Unable to download PDF. HTTP ' + res.getStatusCode());
        }

        return res.getBodyAsBlob();
    }

    /* ============================================================
     * SAVE SALESFORCE FILE
     * ============================================================ */

    public static Id saveAsSalesforceFile(Id subscriberOrgId, String fileName, Blob pdfBlob) {

        if (subscriberOrgId == null) {
            throw buildError('Subscriber Org Id is required.');
        }

        if (pdfBlob == null || pdfBlob.size() == 0) {
            throw buildError('PDF data is empty.');
        }

        ContentVersion cv = new ContentVersion();
        cv.Title                  = fileName;
        cv.PathOnClient           = fileName;
        cv.VersionData            = pdfBlob;
        cv.FirstPublishLocationId = subscriberOrgId;
        insert cv;

        // ContentDocumentId is not populated after insert; re-query it
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1]
               .ContentDocumentId;
    }
}