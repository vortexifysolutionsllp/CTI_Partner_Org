public with sharing class ErrorLogSyncService {

    public static ErrorLogSyncResponseDTO process(
        ErrorLogSyncRequestDTO requestDto
    ) {

        List<ErrorLogSyncResponseDTO.ErrorLogResult> results =
            new List<ErrorLogSyncResponseDTO.ErrorLogResult>();

        /*
         * ============================================================
         * 1. VALIDATE REQUEST
         * ============================================================
         */

        if (requestDto == null) {

            return ErrorLogSyncResponseDTO.failure(
                'Request payload is required',
                'INVALID_REQUEST'
            );
        }


        /*
         * ============================================================
         * 2. READ SUBSCRIBER USAGE
         *
         * The Subscriber Org sends:
         *
         * {
         *     "subscriberUsage": {
         *         "subscriberOrgId": "...",
         *         "status": "...",
         *         "assignedPhoneNumbers": "...",
         *         "currentBalance": ...
         *     }
         * }
         * ============================================================
         */

        String subscriberOrgId;
        String incomingStatus;
        Decimal incomingBalance;

        List<String> incomingPhoneNumbers =
            new List<String>();


        if (requestDto != null) {

            subscriberOrgId =
                requestDto.subscriberOrgId;

            incomingStatus =
                requestDto.status;

            incomingBalance =
                requestDto.currentBalance;


            /*
             * assignedPhoneNumbers comes from Subscriber Org
             * as a comma-separated String.
             */
            if (
                String.isNotBlank(
                    requestDto.assignedPhoneNumbers
                )
            ) {

                for (
                    String phoneNumber :
                    requestDto.assignedPhoneNumbers
                        .split(',')
                ) {

                    if (String.isNotBlank(phoneNumber)) {

                        incomingPhoneNumbers.add(
                            phoneNumber.trim()
                        );
                    }
                }
            }
        }


        /*
         * ============================================================
         * 3. FIND SUBSCRIBER ORG
         *
         * Match incoming Org Id against OrgId__c.
         * ============================================================
         */

        VTXY_SubscriberOrg__c subscriberOrg;

        if (String.isNotBlank(subscriberOrgId)) {

            List<VTXY_SubscriberOrg__c> subscriberOrgs = [

                SELECT Id,
                       OrgId__c,
                       Status__c,
                       Current_Balance__c,
                       Previous_Balance__c,
                       Assigned_Phone_Numbers__c

                FROM VTXY_SubscriberOrg__c

                WHERE OrgId__c = :subscriberOrgId

                LIMIT 1
            ];

            if (!subscriberOrgs.isEmpty()) {

                subscriberOrg =
                    subscriberOrgs[0];
            }
        }


        /*
         * ============================================================
         * 4. PREPARE RESPONSE INFORMATION
         * ============================================================
         */

        Decimal previousBalance;

        List<String> finalPhoneNumbers =
            new List<String>();

        ErrorLogSyncResponseDTO.PhoneNumberChange phoneChanges =
            new ErrorLogSyncResponseDTO.PhoneNumberChange();


        /*
         * ============================================================
         * 5. UPDATE SUBSCRIBER ORG
         * ============================================================
         */

        if (subscriberOrg != null) {


            /*
             * --------------------------------------------------------
             * STATUS
             * --------------------------------------------------------
             */

            subscriberOrg.Status__c =
                incomingStatus;


            /*
             * --------------------------------------------------------
             * BALANCE
             *
             * Existing Current Balance is copied to
             * Previous Balance before the new balance
             * is stored.
             * --------------------------------------------------------
             */

            if (subscriberOrg.Current_Balance__c != null) {

                previousBalance =
                    subscriberOrg.Current_Balance__c;

                subscriberOrg.Previous_Balance__c =
                    subscriberOrg.Current_Balance__c;
            }

            subscriberOrg.Current_Balance__c =
                Decimal.valueOf(incomingBalance);


            /*
             * --------------------------------------------------------
             * PHONE NUMBERS
             * --------------------------------------------------------
             */

            List<String> existingPhoneNumbers =
                new List<String>();


            /*
             * Read existing numbers from Subscriber Org.
             */
            if (
                String.isNotBlank(
                    subscriberOrg.Assigned_Phone_Numbers__c
                )
            ) {

                for (
                    String phoneNumber :
                    subscriberOrg.Assigned_Phone_Numbers__c
                        .split(',')
                ) {

                    if (String.isNotBlank(phoneNumber)) {

                        existingPhoneNumbers.add(
                            phoneNumber.trim()
                        );
                    }
                }
            }


            /*
             * Convert existing and incoming numbers to Sets
             * for comparison.
             */
            Set<String> existingPhoneSet =
                new Set<String>(
                    existingPhoneNumbers
                );

            Set<String> incomingPhoneSet =
                new Set<String>(
                    incomingPhoneNumbers
                );


            /*
             * --------------------------------------------------------
             * FIND REMOVED NUMBERS
             *
             * Existing number is not present in incoming list.
             * --------------------------------------------------------
             */

            for (
                String existingPhone :
                existingPhoneSet
            ) {

                if (
                    !incomingPhoneSet.contains(
                        existingPhone
                    )
                ) {

                    phoneChanges.removed.add(
                        existingPhone
                    );
                }
            }


            /*
             * --------------------------------------------------------
             * FIND ADDED NUMBERS
             *
             * Incoming number does not exist currently.
             * --------------------------------------------------------
             */

            for (
                String incomingPhone :
                incomingPhoneSet
            ) {

                if (
                    !existingPhoneSet.contains(
                        incomingPhone
                    )
                ) {

                    phoneChanges.added.add(
                        incomingPhone
                    );
                }
            }


            /*
             * --------------------------------------------------------
             * DETERMINE PHONE NUMBER ACTION
             * --------------------------------------------------------
             */

            if (
                phoneChanges.added.isEmpty() &&
                phoneChanges.removed.isEmpty()
            ) {

                phoneChanges.action =
                    'NO_CHANGE';

            } else {

                phoneChanges.action =
                    'UPDATED';
            }


            /*
             * --------------------------------------------------------
             * UPDATE ASSIGNED PHONE NUMBERS
             *
             * Incoming list is the source of truth.
             * --------------------------------------------------------
             */

            if (
                !phoneChanges.added.isEmpty() ||
                !phoneChanges.removed.isEmpty()
            ) {

                finalPhoneNumbers =
                    incomingPhoneNumbers;

                subscriberOrg.Assigned_Phone_Numbers__c =
                    String.join(
                        finalPhoneNumbers,
                        ', '
                    );

            } else {

                /*
                 * No change required.
                 */
                finalPhoneNumbers =
                    existingPhoneNumbers;
            }


            /*
             * --------------------------------------------------------
             * SAVE SUBSCRIBER ORG
             * --------------------------------------------------------
             */

            update subscriberOrg;
        }


        /*
         * ============================================================
         * 6. NO ERROR LOGS
         * ============================================================
         */

        if (
            requestDto.errorLogs == null ||
            requestDto.errorLogs.isEmpty()
        ) {

            ErrorLogSyncResponseDTO response =
                ErrorLogSyncResponseDTO.success(
                    results
                );

            response.status =
                'SYNCED';

            response.subscriberOrgId =
                subscriberOrgId;


            if (subscriberOrg != null) {

                response.subscriberOrgRecordId =
                    subscriberOrg.Id;

                response.subscriberOrgStatus =
                    subscriberOrg.Status__c;

                response.previousBalance =
                    previousBalance;

                response.currentBalance =
                    subscriberOrg.Current_Balance__c;

                response.assignedPhoneNumbers =
                    finalPhoneNumbers;

            } else {

                /*
                 * Subscriber Org was not found.
                 * Return incoming values.
                 */
                response.currentBalance =
                    incomingBalance;

                response.assignedPhoneNumbers =
                    incomingPhoneNumbers;
            }


            response.phoneNumberChanges =
                phoneChanges;

            return response;
        }


        /*
         * ============================================================
         * 7. CREATE CASES FOR ERROR LOGS
         * ============================================================
         */

        List<Case> casesToInsert =
            new List<Case>();

        List<ErrorLogSyncRequestDTO.ErrorLogWrapper> logs =
            requestDto.errorLogs;


        for (
            ErrorLogSyncRequestDTO.ErrorLogWrapper logRecord :
            logs
        ) {

            Case newCase =
                new Case();


            /*
             * Subject
             */
            newCase.Subject =
                'Error: ' +
                (
                    String.isBlank(
                        logRecord.className
                    )
                        ? 'Unknown'
                        : logRecord.className
                ) +
                '.' +
                (
                    String.isBlank(
                        logRecord.methodName
                    )
                        ? 'Unknown'
                        : logRecord.methodName
                );


            /*
             * Description
             */
            newCase.Description =
                buildCaseDescription(
                    logRecord
                );


            /*
             * Case fields
             */
            newCase.Origin =
                'API';

            newCase.Priority =
                'High';


            /*
             * Link Case to Subscriber Org.
             */
            if (subscriberOrg != null) {

                newCase.Subscriber_Org__c =
                    subscriberOrg.Id;
            }


            casesToInsert.add(
                newCase
            );
        }


        /*
         * ============================================================
         * 8. INSERT CASES
         * ============================================================
         */

        Database.SaveResult[] saveResults =
            Database.insert(
                casesToInsert,
                false
            );


        for (
            Integer i = 0;
            i < saveResults.size();
            i++
        ) {

            Database.SaveResult saveResult =
                saveResults[i];

            ErrorLogSyncResponseDTO.ErrorLogResult result =
                new ErrorLogSyncResponseDTO.ErrorLogResult();


            result.errorLogId =
                logs[i].id;


            if (saveResult.isSuccess()) {

                result.status =
                    'SYNCED';

                result.caseId =
                    saveResult.getId();

            } else {

                result.status =
                    'FAILED';


                if (
                    saveResult.getErrors() != null &&
                    !saveResult.getErrors().isEmpty()
                ) {

                    result.message =
                        saveResult
                            .getErrors()[0]
                            .getMessage();

                    result.errorCode =
                        String.valueOf(
                            saveResult
                                .getErrors()[0]
                                .getStatusCode()
                        );
                }
            }


            results.add(
                result
            );
        }


        /*
         * ============================================================
         * 9. DETERMINE ERROR LOG RESULT
         * ============================================================
         */

        Boolean hasFailure =
            false;

        Boolean hasSuccess =
            false;


        for (
            ErrorLogSyncResponseDTO.ErrorLogResult result :
            results
        ) {

            if (result.status == 'SYNCED') {

                hasSuccess =
                    true;
            }

            if (result.status == 'FAILED') {

                hasFailure =
                    true;
            }
        }


        /*
         * ============================================================
         * 10. BUILD RESPONSE
         * ============================================================
         */

        ErrorLogSyncResponseDTO response =
            ErrorLogSyncResponseDTO.success(
                results
            );


        response.subscriberOrgId =
            subscriberOrgId;


        if (subscriberOrg != null) {

            response.subscriberOrgRecordId =
                subscriberOrg.Id;

            response.subscriberOrgStatus =
                subscriberOrg.Status__c;

            response.previousBalance =
                previousBalance;

            response.currentBalance =
                subscriberOrg.Current_Balance__c;

            response.assignedPhoneNumbers =
                finalPhoneNumbers;

        } else {

            response.currentBalance =
                incomingBalance;

            response.assignedPhoneNumbers =
                incomingPhoneNumbers;
        }


        /*
         * Phone number changes.
         */
        response.phoneNumberChanges =
            phoneChanges;


        /*
         * ============================================================
         * 11. OVERALL RESPONSE STATUS
         * ============================================================
         */

        if (hasFailure && hasSuccess) {

            response.status =
                'PARTIAL';

        } else if (hasFailure) {

            response.success =
                false;

            response.status =
                'FAILED';

        } else {

            response.status =
                'SYNCED';
        }


        return response;
    }


    /*
     * ================================================================
     * BUILD CASE DESCRIPTION
     * ================================================================
     */

    private static String buildCaseDescription(
        ErrorLogSyncRequestDTO.ErrorLogWrapper logRecord
    ) {

        List<String> lines =
            new List<String>();


        lines.add(
            'Error Log ID: ' +
            logRecord.id
        );

        lines.add(
            'Name: ' +
            logRecord.name
        );

        lines.add(
            'Class: ' +
            logRecord.className
        );

        lines.add(
            'Method: ' +
            logRecord.methodName
        );

        lines.add(
            'Component: ' +
            logRecord.component
        );

        lines.add(
            'Log Level: ' +
            logRecord.logLevel
        );

        lines.add(
            'Status: ' +
            logRecord.status
        );

        lines.add(
            'Message: ' +
            logRecord.message
        );

        lines.add(
            'Error Code: ' +
            logRecord.errorCode
        );

        lines.add(
            'Correlation ID: ' +
            logRecord.correlationId
        );

        lines.add(
            'Related Record ID: ' +
            logRecord.relatedRecordId
        );

        lines.add(
            'Created Date: ' +
            logRecord.createdDate
        );


        lines.add('');

        lines.add(
            'Stack Trace:'
        );

        lines.add(
            logRecord.stackTrace
        );


        lines.add('');

        lines.add(
            'Payload JSON:'
        );

        lines.add(
            logRecord.payloadJSON
        );


        lines.add('');

        lines.add(
            'Context JSON:'
        );

        lines.add(
            logRecord.contextJSON
        );


        return String.join(
            lines,
            '\n'
        );
    }
}