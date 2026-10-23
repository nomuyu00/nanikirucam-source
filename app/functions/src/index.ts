/**
 * なにきるカム（仮）の Firebase Functions（2nd gen、東京リージョン）。
 * 1 関数 1 ファイル。純粋なロジックは `lib/`、Firestore を使う本体は `core/`。
 */
export { publishProblem } from './publishProblem';
export { answerProblem } from './answerProblem';
export { renderProblemPage } from './renderProblemPage';
export { pickDaily } from './pickDaily';
export { notifyDaily } from './notifyDaily';
export { weeklyDigest } from './weeklyDigest';
export { autoPost } from './autoPost';
export { revenuecatWebhook } from './revenuecatWebhook';
export { ensureUser } from './ensureUser';
export { applyReferral } from './applyReferral';
export { reportProblem } from './reportProblem';
export { deleteMyData } from './deleteMyData';
