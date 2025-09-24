import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import fetch from "node-fetch";

// Google Apps Script Web App URLを環境変数から取得
// 統一されたURLを使用
const getAppsScriptUrl = (): string => {
  // 優先順位: gas.url > google.apps_script_url > googleappsscript.url > google_apps_script.url
  const configUrl = functions.config()?.gas?.url ||
                    functions.config()?.google?.apps_script_url ||
                    functions.config()?.googleappsscript?.url ||
                    functions.config()?.google_apps_script?.url;

  const envUrl = process.env.GOOGLE_APPS_SCRIPT_URL;

  const url = configUrl || envUrl || "";

  if (!url) {
    console.error("Google Apps Script URL is not configured in any expected location");
  } else {
    console.log("Using Google Apps Script URL:", url);
  }

  return url;
};

// テンプレートデータの型定義
interface TemplateQuestion {
  question: string;
  type: string;
  required: boolean;
  options?: string[];
  scaleMin?: number;
  scaleMax?: number;
  scaleMinLabel?: string;
  scaleMaxLabel?: string;
  placeholder?: string;
}

interface FormTemplate {
  title: string;
  description: string;
  type: string;
  category: string;
  questions: TemplateQuestion[];
  instructions?: string;
  estimatedMinutes?: number;
  userEmail?: string; // ユーザーメールアドレスを追加
}

// Google Apps Script経由でフォームを作成
export const createGoogleFormViaAppsScript = functions.https.onCall(
  async (data, context) => {
    // 認証チェック
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const template: FormTemplate = data.template;
    const customTitle = data.customTitle || template.title;

    if (!template || !template.questions) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Template with questions is required"
      );
    }

    // Apps Script URLを取得
    const APPS_SCRIPT_URL = getAppsScriptUrl();
    if (!APPS_SCRIPT_URL) {
      console.error("Google Apps Script URL is not configured in any location");
      console.log("Available config:", JSON.stringify(functions.config(), null, 2));
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Google Apps Script URLが設定されていません。管理者に連絡してください。"
      );
    }

    try {
      console.log("Creating form via Google Apps Script...");
      console.log("Title:", customTitle);
      console.log("Questions count:", template.questions.length);

      // ユーザーのメールアドレスを取得（複数のソースから優先順位をつけて取得）
      const authUserId = context.auth.uid;
      const userDoc = await admin.firestore().collection("users").doc(authUserId).get();
      const userData = userDoc.data();

      // メールアドレスの優先順位：
      // 1. Googleアカウント連携時に保存されたメール (googleEmail) - 設定画面で連携したアカウント
      // 2. テンプレートで明示的に指定されたメール
      // 3. Firestoreのユーザードキュメントのメール
      // 4. Firebase Authのメールアドレス
      let userEmail = userData?.googleEmail || template.userEmail || userData?.email || null;

      console.log("User document data:", {
        hasGoogleEmail: !!userData?.googleEmail,
        hasDocEmail: !!userData?.email,
        googleEmail: userData?.googleEmail,
        docEmail: userData?.email
      });

      // Firebase Authからもメールを取得を試みる（最後の手段）
      if (!userEmail) {
        try {
          const authUser = await admin.auth().getUser(authUserId);
          userEmail = authUser.email || null;
        } catch (authError) {
          console.warn("Failed to get email from Firebase Auth:", authError);
        }
      }

      // Firebase Authのメールアドレスを別途取得（userEmailと異なる場合のみ）
      let firebaseEmail: string | null = null;
      try {
        const authUser = await admin.auth().getUser(authUserId);
        firebaseEmail = authUser.email || null;

        // userEmailがない場合はfirebaseEmailを使用
        if (!userEmail && firebaseEmail) {
          userEmail = firebaseEmail;
        }
      } catch (e) {
        console.warn("Failed to get Firebase Auth email:", e);
      }

      console.log("Final email addresses:", {
        primaryEmail: userEmail,  // 設定画面で連携したGoogleアカウント（優先）
        firebaseEmail: firebaseEmail,  // Firebase Authのメール
        willUseForForm: userEmail || firebaseEmail || "No email available"
      });

      // Google Apps Scriptに送信するデータ
      const requestData = {
        action: "createForm",
        template: {
          title: customTitle,
          description: template.description,
          instructions: template.instructions,
          questions: template.questions,
        },
        userEmail: userEmail, // Googleアカウントのメールアドレス
        firebaseEmail: firebaseEmail, // Firebase Authのメールアドレス
      };

      console.log("===== Sending data to Google Apps Script =====");
      console.log("Request data structure:");
      console.log("- action:", requestData.action);
      console.log("- userEmail:", requestData.userEmail);
      console.log("- firebaseEmail:", requestData.firebaseEmail);
      console.log("- template.title:", requestData.template.title);
      console.log("Full request data:", JSON.stringify(requestData));
      console.log("=============================================");

      // Google Apps Script Web Appを呼び出し（リトライ機構付き）
      let response: any;
      let lastError: Error | null = null;
      const maxRetries = 3;

      for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          console.log(`Attempt ${attempt}/${maxRetries} to call Apps Script`);

          // タイムアウトPromiseを作成
          const timeoutPromise = new Promise((_, reject) => {
            setTimeout(() => reject(new Error('Request timed out')), 30000); // 30秒タイムアウト
          });

          // fetchとタイムアウトのraceを実行
          const fetchPromise = fetch(APPS_SCRIPT_URL, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "User-Agent": "Firebase-Functions/1.0",
              "Accept": "application/json",
            },
            body: JSON.stringify(requestData),
          });

          response = await Promise.race([fetchPromise, timeoutPromise]);

          if (response.ok) {
            break; // 成功した場合はループを抜ける
          }

          console.error(`Apps Script returned status ${response.status}`);
          if (attempt < maxRetries) {
            console.log(`Retrying after ${attempt * 1000}ms...`);
            await new Promise(resolve => setTimeout(resolve, attempt * 1000));
          }
        } catch (error: any) {
          lastError = error;
          console.error(`Attempt ${attempt} failed:`, error.message);

          if (error.message === 'Request timed out') {
            console.error('Request timed out after 30 seconds');
          }

          if (attempt < maxRetries) {
            console.log(`Retrying after ${attempt * 1000}ms...`);
            await new Promise(resolve => setTimeout(resolve, attempt * 1000));
          }
        }
      }

      if (!response || !response.ok) {
        const errorMsg = lastError ? lastError.message : `Apps Script returned status ${response?.status || 'unknown'}`;
        throw new Error(errorMsg);
      }

      const responseText = await response.text();
      console.log("Raw response from GAS:", responseText);

      let result: any;
      try {
        result = JSON.parse(responseText);
      } catch (parseError) {
        console.error("Failed to parse GAS response:", parseError);
        console.error("Response was:", responseText);
        throw new Error("Invalid response from Google Apps Script");
      }

      if (!result.success) {
        console.error("GAS returned error:", result);
        throw new Error(result.error || "Failed to create form");
      }

      console.log("===== Form Creation Result from GAS =====");
      console.log("Form ID:", result.formId);
      console.log("Form owner (GAS deployment account):", "yudai61104@gmail.com");
      console.log("Requested editors:", userEmail || "none", firebaseEmail || "none");
      console.log("Shared with (primary):", result.sharedWith);
      console.log("Editor added:", result.editorAdded);
      console.log("Editors successfully added:", result.editorsAdded);
      console.log("Editors failed:", result.editorsFailed);
      console.log("Sharing mode:", result.sharingMode);
      console.log("Link sharing enabled:", result.linkSharingEnabled);
      console.log("=========================================");

      // ユーザーの実験作成履歴を記録
      const userId = context.auth.uid;
      await admin.firestore().collection("form_creation_logs").add({
        userId: userId,
        formId: result.formId,
        templateTitle: template.title,
        templateCategory: template.category,
        customTitle: customTitle,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        formUrl: result.formUrl,
        editUrl: result.editUrl,
        createdVia: "GoogleAppsScript",
        sharedWith: result.sharedWith || null, // undefined を null に変換
        editorAdded: result.editorAdded || false, // undefined を false に変換
        sharingMode: result.sharingMode || "unknown", // undefined を "unknown" に変換
      });

      // ユーザーのGoogleメールアドレスをFirestoreに保存（今後の使用のため）
      if (userEmail && !userData?.googleEmail) {
        await admin.firestore().collection("users").doc(authUserId).update({
          googleEmail: userEmail,
          googleEmailUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return {
        success: true,
        formId: result.formId,
        formUrl: result.formUrl,
        editUrl: result.editUrl,
        directEditUrl: result.directEditUrl || result.editUrl, // undefined の場合は editUrl を使用
        sharedWith: result.sharedWith || userEmail || null,
        editorAdded: result.editorAdded || false,
        editorsAdded: result.editorsAdded || [], // 追加されたエディターリスト
        editorsFailed: result.editorsFailed || [], // 失敗したエディターリスト
        sharingMode: result.sharingMode || "unknown",
        linkSharingEnabled: result.linkSharingEnabled || false,
        instruction: result.instruction || null,
        message: result.editorAdded
          ? "フォームが作成され、編集権限が付与されました"
          : "フォームが作成されました（リンクを知っている全員が編集可能）",
      };

    } catch (error: any) {
      console.error("Error creating form via Apps Script:", error);
      
      let errorMessage = "Google Formの作成に失敗しました";
      let errorCode: any = "internal";
      
      if (error.message) {
        errorMessage += `: ${error.message}`;
      }
      
      throw new functions.https.HttpsError(errorCode, errorMessage);
    }
  }
);