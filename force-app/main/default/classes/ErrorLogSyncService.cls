/**
 * DEPLOY TO: Partner Org
 *
 * Converts Subscriber Error Logs into Salesforce Cases.
 */
public with sharing class ErrorLogSyncService {

    public static ErrorLogSyncResponseDTO process(
        ErrorLogSyncRequestDTO request
    ) {

        if (request == null ||
            request.errorLogs == null ||
            request.errorLogs.isEmpty()) {

            return ErrorLogSyncResponseDTO.failure(
                'No Error Logs were provided',
                'NO_ERROR_LOGS'
            );
        }

        List<Case> casesToInsert = new List<Case>();

        /*
         * Keep the source Error Log information aligned
         * with the Case being created.
         */
        List<ErrorLogSyncRequestDTO.ErrorLogWrapper> logsToProcess =
            new List<ErrorLogSyncRequestDTO.ErrorLogWrapper>();

        for (
            ErrorLogSyncRequestDTO.ErrorLogWrapper errorLog :
            request.errorLogs
        ) {

            if (String.isBlank(errorLog.id)) {
                continue;
            }

            Case caseRecord = new Case();

            /*
             * Subject
             */
            String className =
                String.isBlank(errorLog.className)
                    ? 'Unknown Class'
                    : errorLog.className;

            String methodName =
                String.isBlank(errorLog.methodName)
                    ? 'Unknown Method'
                    : errorLog.methodName;

            caseRecord.Subject =
                'Error: ' +
                className +
                '.' +
                methodName;

            /*
             * Description
             *
             * Map ALL Error Log fields into the Case.
             */
            caseRecord.Description =
                buildCaseDescription(errorLog);

            /*
             * Standard Case fields.
             *
             * Only set these if these are valid values
             * in your Partner Org.
             */
            caseRecord.Origin = 'API';
            caseRecord.Priority = 'High';

            casesToInsert.add(caseRecord);
            logsToProcess.add(errorLog);
        }

        if (casesToInsert.isEmpty()) {

            return ErrorLogSyncResponseDTO.failure(
                'No valid Error Logs were found',
                'NO_VALID_ERROR_LOGS'
            );
        }

        /*
         * Insert all Cases together.
         */
        Database.SaveResult[] saveResults =
            Database.insert(casesToInsert, false);

        List<ErrorLogSyncResponseDTO.ErrorLogResult> results =
            new List<ErrorLogSyncResponseDTO.ErrorLogResult>();

        Boolean allSuccessful = true;

        for (Integer i = 0; i < saveResults.size(); i++) {

            Database.SaveResult sr = saveResults[i];

            ErrorLogSyncRequestDTO.ErrorLogWrapper errorLog =
                logsToProcess[i];

            ErrorLogSyncResponseDTO.ErrorLogResult result =
                new ErrorLogSyncResponseDTO.ErrorLogResult();

            result.requestId = errorLog.correlationId;
            result.errorLogId = errorLog.id;

            if (sr.isSuccess()) {

                result.status = 'SYNCED';
                result.caseId = sr.getId();
                result.message = 'Case created successfully';
                result.errorCode = null;

            } else {

                allSuccessful = false;

                result.status = 'FAILED';
                result.caseId = null;
                result.message =
                    sr.getErrors()[0].getMessage();
                result.errorCode =
                    String.valueOf(
                        sr.getErrors()[0].getStatusCode()
                    );
            }

            results.add(result);
        }

        ErrorLogSyncResponseDTO response =
            ErrorLogSyncResponseDTO.success(results);

        /*
         * If at least one Case failed, don't report the
         * entire operation as fully successful.
         */
        if (!allSuccessful) {
            response.success = false;
            response.status = 'PARTIAL';
        }

        return response;
    }


    private static String buildCaseDescription(
        ErrorLogSyncRequestDTO.ErrorLogWrapper errorLog
    ) {

        List<String> lines = new List<String>();

        lines.add('===== Error Log Details =====');

        lines.add(
            'Error Log Id: ' +
            String.valueOf(errorLog.id)
        );

        lines.add(
            'Name: ' +
            String.valueOf(errorLog.name)
        );

        lines.add(
            'Class Name: ' +
            String.valueOf(errorLog.className)
        );

        lines.add(
            'Method Name: ' +
            String.valueOf(errorLog.methodName)
        );

        lines.add(
            'Component: ' +
            String.valueOf(errorLog.component)
        );

        lines.add(
            'Log Level: ' +
            String.valueOf(errorLog.logLevel)
        );

        lines.add(
            'Status: ' +
            String.valueOf(errorLog.status)
        );

        lines.add(
            'Error Code: ' +
            String.valueOf(errorLog.errorCode)
        );

        lines.add(
            'Correlation Id: ' +
            String.valueOf(errorLog.correlationId)
        );

        lines.add(
            'Related Record Id: ' +
            String.valueOf(errorLog.relatedRecordId)
        );

        lines.add(
            'Created Date: ' +
            String.valueOf(errorLog.createdDate)
        );

        lines.add('');

        lines.add('===== Message =====');

        lines.add(
            String.valueOf(errorLog.message)
        );

        lines.add('');

        lines.add('===== Stack Trace =====');

        lines.add(
            String.valueOf(errorLog.stackTrace)
        );

        lines.add('');

        lines.add('===== Payload JSON =====');

        lines.add(
            String.valueOf(errorLog.payloadJSON)
        );

        lines.add('');

        lines.add('===== Context JSON =====');

        lines.add(
            String.valueOf(errorLog.contextJSON)
        );

        return String.join(lines, '\n');
    }
}