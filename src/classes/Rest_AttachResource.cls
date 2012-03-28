@RestResource(urlMapping='/Attach/*')
global with sharing class Rest_AttachResource {
    
    @HttpPost
    global static String doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        System.debug('received req: ' + req);
        System.debug('received res: ' + res);
        
        //Variables from header
        String recordId = '';
        String parentId = '';
        String fileName = '';
        Blob base64BlobValue = null;
        String contentType = '';
        
        for (String headerName : req.headers.keySet()) {
            System.debug(headerName + ':' + req.headers.get(headerName));
            String headerValue = req.headers.get(headerName);
            if (headerName == 'upload_parentid')
                parentId = headerValue;
            if (headerName == 'upload_recordid')
                recordId = headerValue;
            if (headerName == 'upload_fileName')
                fileName = headerValue;
            if (headerName == 'upload_contenttype')
                contentType = headerValue;
        }
        
        base64BlobValue = req.requestBody;
        
        
        //If recordId is blank this is the first part of a multi piece upload
        if (recordId == null || recordId == '') {
            Attachment newAttachment = new Attachment(
                ParentId = parentId,
                //Body = EncodingUtil.Base64Decode(base64BlobValue),
                Body = base64BlobValue,
                Name = fileName,
                ContentType = contentType
            );
            Database.insert(newAttachment);
            
            //Return the new attachment Id so the client can append to it.
            return newAttachment.Id;
        }
        else {
            for (Attachment atm : [SELECT Id, Body FROM Attachment WHERE Id = :recordId]){
                //Take the body of the current attachment, convert to base64 string, append base64 value sent from page, then convert back to binary for the body
                Database.update(
                    new Attachment(
                        Id = recordId,
                        Body = EncodingUtil.Base64Decode(EncodingUtil.Base64Encode(atm.Body) + base64BlobValue)
                    ));
            }
            
            //Return the Id of the attachment we are currently processing
            return recordId;
        }
        
        
        return 'returning from doPost...';
    }

}