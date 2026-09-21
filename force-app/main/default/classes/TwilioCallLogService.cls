public without sharing class TwilioCallLogService {

    private static final String NAMED_CREDENTIAL =
        'callout:Twilio';

    private static final Integer PAGE_SIZE = 250;

    public class CallRecord {

        public String sid;
        public String fromNumber;
        public String toNumber;
        public String direction;
        public String status;

        public Datetime startTime;
        public Datetime endTime;

        public Integer duration;

        public Decimal price;
        public String priceUnit;
    }

    public class FetchResult {

        public List<CallRecord> calls;
        public String nextPageUri;

        public FetchResult() {
            calls = new List<CallRecord>();
        }
    }

    public static FetchResult fetchCalls(
        String accountSid,
        Date billingStartDate,
        Date billingEndDate,
        String nextPageUri
    ) {

        if (String.isBlank(accountSid)) {
            throw new CalloutException(
                'Twilio Account SID is required.'
            );
        }

        if (
            billingStartDate == null ||
            billingEndDate == null
        ) {
            throw new CalloutException(
                'Billing dates are required.'
            );
        }

        HttpRequest request =
            new HttpRequest();

        request.setMethod('GET');
        request.setTimeout(120000);

        String endpoint;

        /*
         * FIRST PAGE
         */
        if (String.isBlank(nextPageUri)) {

            String encodedAccountSid =
                EncodingUtil.urlEncode(
                    accountSid,
                    'UTF-8'
                );

            Date exclusiveEndDate =
                billingEndDate.addDays(1);

            endpoint =
                NAMED_CREDENTIAL +
                '/2010-04-01/Accounts/' +
                encodedAccountSid +
                '/Calls.json' +
                '?PageSize=' +
                PAGE_SIZE +
                '&StartTimeAfter=' +
                String.valueOf(
                    billingStartDate
                ) +
                '&StartTimeBefore=' +
                String.valueOf(
                    exclusiveEndDate
                );

        } else {

            /*
             * TWILIO NEXT PAGE
             */
            endpoint =
                NAMED_CREDENTIAL +
                nextPageUri;
        }

        request.setEndpoint(endpoint);

        HttpResponse response =
            new Http().send(request);

        Integer statusCode =
            response.getStatusCode();

        if (
            statusCode < 200 ||
            statusCode >= 300
        ) {

            throw new CalloutException(
                'Twilio API failed. HTTP Status: ' +
                statusCode +
                '. Response: ' +
                response.getBody()
            );
        }

        return parseResponse(
            response.getBody()
        );
    }

    private static FetchResult parseResponse(
        String responseBody
    ) {

        FetchResult result =
            new FetchResult();

        if (String.isBlank(responseBody)) {
            return result;
        }

        Map<String, Object> root =
            (Map<String, Object>)
            JSON.deserializeUntyped(
                responseBody
            );

        Object callsObject =
            root.get('calls');

        if (callsObject != null) {

            List<Object> calls =
                (List<Object>) callsObject;

            for (Object callObject : calls) {

                Map<String, Object> callMap =
                    (Map<String, Object>)
                    callObject;

                CallRecord record =
                    new CallRecord();

                record.sid =
                    (String) callMap.get('sid');

                record.fromNumber =
                    (String) callMap.get('from');

                record.toNumber =
                    (String) callMap.get('to');

                record.direction =
                    (String) callMap.get('direction');

                record.status =
                    (String) callMap.get('status');

                System.debug(
    'TWILIO RAW START TIME = ' +
    callMap.get('start_time')
);

System.debug(
    'TWILIO RAW END TIME = ' +
    callMap.get('end_time')
);

                record.startTime =
                    parseTwilioDateTime(
                        (String)
                        callMap.get('start_time')
                    );

                record.endTime =
                    parseTwilioDateTime(
                        (String)
                        callMap.get('end_time')
                    );

                System.debug(
    'PARSED START TIME = ' +
    record.startTime
);

System.debug(
    'PARSED END TIME = ' +
    record.endTime
);

                String durationValue =
                    (String)
                    callMap.get('duration');

                if (
                    !String.isBlank(
                        durationValue
                    )
                ) {

                    try {

                        record.duration =
                            Integer.valueOf(
                                durationValue
                            );

                    } catch (Exception e) {

                        record.duration = 0;
                    }

                } else {

                    record.duration = 0;
                }

                String priceValue =
                    (String)
                    callMap.get('price');

                if (
                    !String.isBlank(
                        priceValue
                    )
                ) {

                    try {

                        record.price =
                            Decimal.valueOf(
                                priceValue
                            );

                    } catch (Exception e) {

                        record.price = 0;
                    }

                } else {

                    record.price = 0;
                }

                record.priceUnit =
                    (String)
                    callMap.get('price_unit');

                result.calls.add(record);
            }
        }

        result.nextPageUri =
            (String)
            root.get('next_page_uri');

        return result;
    }

       private static final List<String> MONTH_ABBREVIATIONS = new List<String>{
        'Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'
    };

    /*
     * Twilio v2010 sends RFC 2822, e.g. "Mon, 21 Sep 2026 06:41:07 +0000".
     * ISO 8601 strings are still handled by parseIsoDateTime().
     */
    private static Datetime parseTwilioDateTime(String value) {

        if (String.isBlank(value)) {
            return null;
        }

        String s = value.trim();

        // ISO 8601, e.g. 2026-09-21T06:41:07Z
        if (Pattern.matches('^\\d{4}-\\d{2}-\\d{2}.*', s)) {
            return parseIsoDateTime(s);
        }

        // RFC 2822
        try {
            Integer commaIdx = s.indexOf(',');
            if (commaIdx > -1) {
                s = s.substring(commaIdx + 1).trim();
            }

            // [0]=21 [1]=Sep [2]=2026 [3]=06:41:07 [4]=+0000
            List<String> parts = s.split('\\s+');

            Integer day   = Integer.valueOf(parts[0]);
            Integer month = MONTH_ABBREVIATIONS.indexOf(parts[1].substring(0, 3)) + 1;
            Integer year  = Integer.valueOf(parts[2]);

            if (month < 1) {
                throw new TypeException('Unknown month: ' + parts[1]);
            }

            List<String> hms = parts[3].split(':');

            Datetime dt = Datetime.newInstanceGmt(
                year, month, day,
                Integer.valueOf(hms[0]),
                Integer.valueOf(hms[1]),
                Integer.valueOf(hms[2])
            );

            // Convert to UTC if an offset is present (Twilio normally sends +0000)
            if (parts.size() > 4 && parts[4].length() == 5) {
                Integer sign = parts[4].startsWith('-') ? -1 : 1;
                Integer offsetMinutes = sign * (
                    Integer.valueOf(parts[4].substring(1, 3)) * 60 +
                    Integer.valueOf(parts[4].substring(3, 5))
                );
                dt = dt.addMinutes(-offsetMinutes);
            }

            return dt;

        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Unable to parse Twilio datetime. Value = ' + value +
                ', Error = ' + e.getMessage()
            );
            return null;
        }
    }

    /*
     * Your original parser, renamed. Handles ISO 8601 only.
     */
    private static Datetime parseIsoDateTime(String value) {

        if (String.isBlank(value)) {
            return null;
        }

        try {

            String normalized = value.trim();

            // Remove trailing Z
            if (normalized.endsWith('Z')) {
                normalized = normalized.substring(0, normalized.length() - 1);
            }

            // Convert T to space
            normalized = normalized.replace('T', ' ');

            // Remove milliseconds
            Integer decimalPosition = normalized.indexOf('.');
            if (decimalPosition > 0) {
                normalized = normalized.substring(0, decimalPosition);
            }

            // Remove timezone offset if one exists
            Integer plusPosition  = normalized.lastIndexOf('+');
            Integer minusPosition = normalized.lastIndexOf('-');

            Integer timezonePosition = -1;

            if (plusPosition > 10) {
                timezonePosition = plusPosition;
            }

            if (minusPosition > 10 && minusPosition > timezonePosition) {
                timezonePosition = minusPosition;
            }

            if (timezonePosition > 0) {
                normalized = normalized.substring(0, timezonePosition);
            }

            return Datetime.valueOfGmt(normalized);

        } catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'Unable to parse ISO datetime. Value = ' + value +
                ', Error = ' + e.getMessage()
            );

            return null;
        }
    }
}
