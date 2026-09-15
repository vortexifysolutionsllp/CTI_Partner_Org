/**
 * DEPLOY TO: Partner Org
 *
 * Exposes:
 * /services/apexrest/vtxp/v1/error-log/sync
 *
 * Receives Error Logs from Subscriber Org,
 * creates Cases, and returns the result for each Error Log.
 */
@RestResource(urlMapping='/vtxp/v1/error-log/sync')
global without sharing class ErrorLogApi {

    @HttpPost
    global static void syncErrorLogs() {

        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        res.addHeader('Content-Type', 'application/json');

        ErrorLogSyncResponseDTO responseDto;

        try {

            if (req.requestBody == null ||
                req.requestBody.size() == 0) {

                responseDto =
                    ErrorLogSyncResponseDTO.failure(
                        'Request body is required',
                        'INVALID_REQUEST'
                    );

                res.statusCode = 400;
                res.responseBody =
                    Blob.valueOf(JSON.serialize(responseDto));

                return;
            }

            /*
             * THIS IS WHERE DESERIALIZATION HAPPENS.
             *
             * Subscriber JSON
             *        ↓
             * ErrorLogSyncRequestDTO
             */
            ErrorLogSyncRequestDTO requestDto =
                (ErrorLogSyncRequestDTO) JSON.deserialize(
                    req.requestBody.toString(),
                    ErrorLogSyncRequestDTO.class
                );

            responseDto =
                ErrorLogSyncService.process(requestDto);

            res.statusCode =
                responseDto.success ? 200 : 400;

        } catch (Exception ex) {

            responseDto =
                ErrorLogSyncResponseDTO.failure(
                    'Unexpected error: ' + ex.getMessage(),
                    'INTERNAL_ERROR'
                );

            res.statusCode = 500;
        }

        res.responseBody =
            Blob.valueOf(
                JSON.serialize(responseDto, true)
            );
    }
}