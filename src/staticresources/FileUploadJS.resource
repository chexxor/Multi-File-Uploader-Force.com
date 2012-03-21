

	
	
	// Simple JavaScript Templating
	// John Resig - http://ejohn.org/ - MIT Licensed
	(function(){
	  var cache = {};
	  
	  this.tmpl = function tmpl(str, data){
		// Figure out if we're getting a template, or if we need to
		// load the template - and be sure to cache the result.
		var fn = !/\W/.test(str) ?
			cache[str] = cache[str] ||
			tmpl(document.getElementById(str).innerHTML) :

			// Generate a reusable function that will serve as a template
			// generator (and which will be cached).
			new Function("obj",
			"var p=[],print=function(){p.push.apply(p,arguments);};" +

			// Introduce the data as local variables using with(){}
			"with(obj){p.push('" +

			// Convert the template into pure JavaScript
			str
			  .replace(/[\r\t\n]/g, " ")
			  .split("<%").join("\t")
			  .replace(/((^|%>)[^\t]*)'/g, "$1\r")
			  .replace(/\t=(.*?)%>/g, "',$1,'")
			  .split("\t").join("');")
			  .split("%>").join("p.push('")
			  .split("\r").join("\\'")
			+ "');}return p.join('');");

			// Provide some basic currying to the user
			return data ? fn( data ) : fn;
		};
	})();
	
	



	var j$ = jQuery.noConflict();
	j$(document).ready(function() {
		//Event listener for click of Upload button
		j$("#uploadButton").click(function() {
			FileUploaderApp.handleClickUpload();
		});

		//Event listener to clear upload details/status bars once upload is complete
		j$("#clear").on('click', function() {
			j$(".upload").remove();
		});
	});
	
	
	// Namespace for the FileUploader app
	var FileUploader = {};
	
	// Constants
	FileUploader.VIEW_URL = '/servlet/servlet.FileDownload?file=';
	//FileUploader.CHUNK_SIZE = 180000;//Must be evenly divisible by 3, if not, data corruption will occur
	FileUploader.CHUNK_SIZE = 60000;//Must be evenly divisible by 3, if not, data corruption will occur
	FileUploader.FILE_INPUT_ID = 'filesInput';

	

	FileUploader.uploadFiles = function(pSelectedFiles, pOnProgress, pOnSuccess, pOnError) {
		var selectedFiles = pSelectedFiles;
		console.log('selectedFiles', selectedFiles);
		// Files remaining to upload are marked by a custom data attribute named 'data-status'
		var pendingFilesElements = j$(".upload[data-status='pending']");

		if (pendingFilesElements.length != 0) {
			//Based on index of the div, get correct file from files array
			for (var i = 0; i < selectedFiles.length; i++) {
				var fileIndex = i;
				var fileToUpload = selectedFiles[fileIndex];
				FileUploader.uploadFile(
						{"file":fileToUpload, "index":fileIndex},
						pOnProgress,
						pOnSuccess,
						pOnError
				);
			}

		} else {
			//All uploads completed, enable the input and buttons
			j$(".uploadBox input").removeAttr("disabled");
			j$(".uploadBox button").removeAttr("disabled").attr("class", "btn");

			//Remove the browse input element and replace it, this essentially removes
			//the selected files and helps prevent duplicate uploads
			j$("#filesInput").replaceWith('<input type="file" name="file" multiple="true" id="filesInput">');
		}
	}
	
	// Uploads a single file.
	FileUploader.uploadFile = function(pFileToUploadInfo, pOnProgress, pOnSuccess, pOnError) {
	
		var onProgress = pOnProgress;
		var onSuccess = pOnSuccess;
		var onError = pOnError;
		var fileToUploadInfo = pFileToUploadInfo;
		var fileToUpload = pFileToUploadInfo["file"];
		var fileIndex = pFileToUploadInfo["fileIndex"];
		var byteChunkPattern = FileUploader.createChunkPatternForFile(fileToUpload);

		// The attachmentId parameter is '' because we are not appending to an existing Attachment.
		FileUploader.uploadFileUsingChunkingPattern(
				'',
				fileToUploadInfo,
				byteChunkPattern,
				function(pFileUploadInfo, pChunkUploaded) {//onProgress
					onProgress(pFileUploadInfo, pChunkUploaded);
				},
				function(pUploadedFileInfo) {//onSuccess
					onSuccess(pUploadedFileInfo);
				},
				function() {//onError
					onError();
				}
		);
	}
	
	// Creates a byte chunk array of the proper length for the specified file.
	FileUploader.createChunkPatternForFile = function(pFileToChunk) {
		//Build the byteChunkPattern array for the current file we are processing. This array is formatted as:
		//['0-179999','180000-359999',etc] and represents the chunks of bytes that will be uploaded individually.
		var byteChunkPattern = new Array();
		var fileToChunk = pFileToChunk;

		//First check to see if file size is less than the chunk size, if so first and only chunk is entire size of file
		if (fileToChunk.size <= FileUploader.CHUNK_SIZE) {
			byteChunkPattern[0] = '0-' + (fileToChunk.size - 1);
		} else {
			//Determine how many whole byte chunks make up the file,
			var numOfFullChunks = Math.floor(fileToChunk.size / FileUploader.CHUNK_SIZE); //i.e. 1.2MB file would be 1000000 / CHUNK_SIZE
			var remainderBytes = fileToChunk.size % FileUploader.CHUNK_SIZE; // would determine remainder of 1200000 bytes that is not a full chunk
			var startByte = 0;
			var endByte = FileUploader.CHUNK_SIZE - 1;

			//Loop through the number of full chunks and build the byteChunkPattern array
			for(i = 0; i < numOfFullChunks; i++){
				byteChunkPattern[i] = startByte + '-' + endByte;

				//Set new start and stop bytes for next iteration of loop
				startByte = endByte + 1;
				endByte += FileUploader.CHUNK_SIZE;
			}

			//Add the last chunk of remaining bytes to the byteChunkArray
			startByte = fileToChunk.size - remainderBytes;
			endByte = fileToChunk.size;
			byteChunkPattern.push(startByte + '-' + endByte);
		}
		
		return byteChunkPattern;
	}

	// Uploads a chunk of bytes.
	// If an recordId is specified, the bytes will be appended to that attachment record.
	FileUploader.uploadFileUsingChunkingPattern = function(pRecordId, pFileToUploadInfo, pByteChunkPattern, pOnProgress, pOnSuccess, pOnError) {
		
		var recordId = pRecordId;
		var fileToUploadInfo = pFileToUploadInfo;
		var fileToUpload = pFileToUploadInfo["file"];
		var onProgress = pOnProgress;
		var onSuccess = pOnSuccess;
		var onError = pOnError;
		
		//Proceed if there are still values in the byteChunkPattern, if none, all piece of the file have been uploaded
		if (pByteChunkPattern.length > 0) {
			
			//Create blobChunk to send to FileReader.
			var blobChunk = FileUploader.sliceChunkFromFileUsingChunkingPattern(fileToUpload, pByteChunkPattern);

			var reader = new FileReader();

			//Create a reader.onload function, which is called after reader activity.
			reader.onloadend = function(evt) {
				
				var insideFileToUploadInfo = fileToUploadInfo;
				
				if (evt.target.readyState != FileReader.DONE) {
					//Error handling for bad read
					error(evt, 'Could not read file.');
				}
				
				//Base 64 encode the data for transmission to the server with JS remoting.
				//window.btoa currently on support by some browsers
				//TODO: What should we do if window.btoa is not supported?
				var base64value = window.btoa(evt.target.result);
				var byteChunkPatternToUpload = pByteChunkPattern;

				//Use JS remoting to send the base64 encoded chunk for uploading
				FileUploadController.attachBlob(parentId,
												recordId,
												fileToUpload.name,
												fileToUpload.type,
												base64value,
												function(result, event) {

					var uploadedFileInfo = insideFileToUploadInfo;
					var uploadedByteChunkPattern = byteChunkPatternToUpload;
					//Proceed if there were no errors with the remoting call
					if (event.status == true) {
						var fileUploadInfo = {"file": uploadedFileInfo["file"], "index":uploadedFileInfo["index"]};
						onProgress(fileUploadInfo, uploadedByteChunkPattern);
						
						//Remove the chunk pattern for the piece just uploaded.
						pByteChunkPattern.shift();

						//All subsequent file chunks will be appended to this record.
						var recordId = result;

						//Call uploadFileUsingChunkingPattern to upload the next piece of the file
						FileUploader.uploadFileUsingChunkingPattern(recordId, uploadedFileInfo, pByteChunkPattern, onProgress, onSuccess, onError);
						
					} else {
						//Something broke in Javascript remoting call
						var uploadError = {
								"errorMessage":"Error in Javascript Remoting call.",
								"result":result,
								"event":event};
						//TODO: Why is this object not passed through to the user callback?
						//  It has value here, but is undefined on user end.
						console.log('uploadError', uploadError);
						onError(uploadError);
					}
				});
			};
			
			//Read the blobChunk as a binary string. When complete, the reader.onloadend function is called.
			reader.readAsBinaryString(blobChunk);

		} else {
			//No more byte chunks to send. The entire file has been sent.
			var fileUploadInfo = {
					"recordid": pRecordId,
					"file":pFileToUploadInfo["file"],
					"fileIndex":pFileToUploadInfo["index"]};
			onSuccess(fileUploadInfo);
		}
	}
	
	// The sliceChunkFromFileUsingChunkingPattern function will slice a chunk out of the specified file and return it.
	FileUploader.sliceChunkFromFileUsingChunkingPattern = function(pCurrentFile, pByteChunkPattern) {
		//Determine the byte range that needs to uploaded, if byteChunkPattern is like... ['0-179999','180000-359999']
		var indexes = pByteChunkPattern[0].split('-'); //get first index range '0-179999' -> ['0','179999']
		var startByte = parseInt(indexes[0]); //0
		var stopByte = parseInt(indexes[1]); //179999
		var blobChunk;
		
		//Slice the part of the file we want to upload, currentFile variable is set in checkForUploads() method that is called before this method
		if (pCurrentFile.webkitSlice) {
			blobChunk = pCurrentFile.webkitSlice(startByte , stopByte + 1);
		} else if (pCurrentFile.mozSlice) {
			blobChunk = pCurrentFile.mozSlice(startByte , stopByte + 1);
		}
		
		return blobChunk;
	}
	
	
	/******************************************************************/
	
	// The FileUploader app attaches to the following elements:
	// .uploadBox
	// .uploadBox input
	// .uploadBox button
	// .upload .statusPercent
	// .upload .name
	// .upload .percentComplete
	// .upload .statusBarPercent
	
	var FileUploaderApp = {};
	
	// This onProgress function will be called whenever a chunk of a file is uploaded.
	FileUploaderApp.onProgress = function(pFileUploadInfo, pChunkUploaded) {
		var fileUploading = pFileUploadInfo["file"];
		var fileIndexUploading = pFileUploadInfo["index"];
		var chunkUploaded = pChunkUploaded;
	
		//Update the percent of the status bar and percent, first determine percent complete
		var chunkStartStopRange = pChunkUploaded[0].split('-'); //get first index range '0-179999' -> ['0','179999']
		var chunkUploadedStopByte = parseInt(chunkStartStopRange[1]); //179999
		var percentComplete = Math.round((chunkUploadedStopByte / fileUploading.size) * 100);
		
		//TODO: Make this better encapsulated. Why doesn't this work?
		var currentFileElement = j$("div[data-index=" + fileIndexUploading + "]");
		currentFileElement.find(".percentComplete").text(percentComplete + '%');
		currentFileElement.find(".statusBarPercent").css('width', percentComplete + '%');
	}
	
	// This onSuccess function will be called whenever a single file is successfully uploaded.
	FileUploaderApp.onSuccess = function(pFileUploadInfo) {
		var recordId = pFileUploadInfo["recordId"];
		var fileUploaded = pFileUploadInfo["file"];
		var fileIndexUploaded = pFileUploadInfo["index"];
		
		//This file has completed, all byte chunks have been uploaded, set status on the div to complete
		var currentFileElement = j$("div[data-index=" + fileIndexUploaded + "]");
		currentFileElement.attr('data-status','complete');

		//Change name of file to link of uploaded attachment
		currentFileElement.find(".name").html('<a href="' + FileUploader.VIEW_URL + recordId + '" target="_blank">' + fileUploaded.name + '</a>');
	}
	
	// This onError function will be called whenever an error occurs when uploading a chunk.
	FileUploaderApp.onError = function(pFileUploadErrorInfo) {
		console.log('onError', pFileUploadErrorInfo);
		var errorMessage = pFileUploadErrorInfo["errorMessage"];
		var uploadResult = pFileUploadErrorInfo["result"];
		var uploadEvent = pFileUploadErrorInfo["event"];
		
		//Add classes to reflect error
		j$();
		//TODO: Make this use jQuery or something to update the upload info boxes on error.
		/*
		pendingFilesElements.attr('data-status','complete');
		pendingFilesElements.addClass('uploadError');
		pendingFilesElements.find(".statusPercent").addClass('statusPercentError');
		pendingFilesElements.attr('title', uploadEvent.message);
		*/
	}
	
	FileUploaderApp.handleDragOver = function(evt) {
		console.log('handleDragOver', evt);
		evt.stopPropagation();
		evt.preventDefault();
		evt.dataTransfer.dropEffect = 'copy';
	}
	
	// Event handler for the Upload button
	FileUploaderApp.handleClickUpload = function() {
	
		// Get the file(s) from the input field
		var selectedFiles = document.getElementById(FileUploader.FILE_INPUT_ID).files;

		console.log('selectedFiles', selectedFiles);
		// Only proceed if there are files selected
		if (selectedFiles.length === 0) {
			alert('Please select a file!');
			return;
		}

		// Disable inputs and buttons during the upload process
		j$(".uploadBox input").attr("disabled", "disabled");
		j$(".uploadBox button").attr({
			disabled: "disabled",
			class: "btnDisabled"
		});

		// Build out the upload divs for each file selected
		for (i = 0; i < selectedFiles.length; i++) {
			var error = '';
			var displaySize = '';
			var selectedFile = selectedFiles[i];
			//Determine file display size
			//Catch any files that are too large.
			if (selectedFile.size > 5242880) {
				displaySize = '>5MB';
				error = 'Error: Too large - max. size 5MB';
				//TODO: Can we remove this file from the list somehow? I can't figure out how.
			} else if (selectedFile.size < 1000000) {
				displaySize = Math.floor(selectedFile.size / 1000) + 'KB';
			} else {
				displaySize = Math.round((selectedFile.size / 1000000) * 10) / 10 + 'MB';
			}
			
			var uploadMarkup = tmpl("uploadItemTmpl", {"index":i, "file":selectedFile, "displaySize":displaySize, "error": error});
			
			//Add markup to the upload box
			j$('.uploadBox').append(uploadMarkup);
		}

		//TODO: Move this dragover bind to somewhere else.
		j$('.uploadBox').bind('dragover', FileUploaderApp.handleDragOver);
		j$('.uploadBox').bind('drop', FileUploaderApp.handleClickUpload);

		//Once elements have been added to the page representing the uploads, start the actual upload process
		FileUploader.uploadFiles(selectedFiles, FileUploaderApp.onProgress, FileUploaderApp.onSuccess, FileUploaderApp.onError);
	}