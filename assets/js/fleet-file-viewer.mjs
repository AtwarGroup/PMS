import {fleetFile} from './fleet-file-storage.mjs?v=2.8.0';
import {openAttachmentViewer} from './attachment-viewer.mjs?v=1';
export function openFleetAttachment(rpc,id,kind='request'){return openAttachmentViewer(()=>fleetFile(rpc,id,kind));}
