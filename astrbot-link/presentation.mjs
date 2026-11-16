/* Furniture actions are authoritative; no room-wide pose substitution. */
import {mapState} from './mapping.mjs';
export const presentationMode='activity';
export function displayState(actor,state,house={},now=Date.now()){
 const mapped=mapState(actor,state,house,now);
 return {...mapped,sourceSleeping:mapped.sleeping,presentationMode};
}
export function validatePresentation(world){return {mode:presentationMode,blanketPoseOverride:false};}
