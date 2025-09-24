// Google Apps Script テスト用簡易版
// 問題を特定するための最小限の実装

function doPost(e) {
  try {
    console.log('=== doPost START ===');
    const data = JSON.parse(e.postData.contents);
    console.log('Action:', data.action);
    console.log('UserEmail:', data.userEmail);
    console.log('FirebaseEmail:', data.firebaseEmail);

    if (data.action === 'createForm') {
      return createFormSimple(data);
    }

    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: 'Unknown action'
    })).setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    console.error('doPost error:', error.toString());
    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: error.toString()
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

function createFormSimple(data) {
  // 変数を最初に宣言
  let form, formId, formUrl, editUrl;
  let response = {
    success: false,
    stage: 'init'
  };

  try {
    const template = data.template;
    const customTitle = data.customTitle || template.title;
    const userEmail = data.userEmail;
    const firebaseEmail = data.firebaseEmail;

    console.log('Creating form with title:', customTitle);
    console.log('UserEmail from data:', userEmail);
    console.log('FirebaseEmail from data:', firebaseEmail);

    // ステージ1: フォーム作成
    response.stage = 'create_form';
    form = FormApp.create(customTitle);
    formId = form.getId();
    formUrl = form.getPublishedUrl();
    editUrl = form.getEditUrl();

    console.log('Form created with ID:', formId);

    // ステージ2: 基本設定
    response.stage = 'basic_settings';
    form.setRequireLogin(false);
    form.setCollectEmail(true);

    // ステージ3: 共有設定
    response.stage = 'sharing_settings';
    let sharingSet = false;
    let editorAdded = false;
    const editorsAdded = [];
    const editorsFailed = [];

    try {
      const formFile = DriveApp.getFileById(formId);

      // リンク共有設定を試みる
      try {
        formFile.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.EDIT);
        sharingSet = true;
        console.log('Link sharing enabled');
      } catch (shareErr) {
        console.log('Could not enable link sharing:', shareErr.toString());
      }

      // 編集者を追加
      if (userEmail && userEmail.includes('@')) {
        try {
          formFile.addEditor(userEmail);
          editorsAdded.push(userEmail);
          editorAdded = true;
          console.log('Added editor:', userEmail);
        } catch (editorErr) {
          console.log('Could not add editor:', userEmail, editorErr.toString());
          editorsFailed.push({email: userEmail, error: editorErr.toString()});
        }
      }

    } catch (fileErr) {
      console.log('File operations error:', fileErr.toString());
    }

    // ステージ4: レスポンス作成
    response = {
      success: true,
      formId: formId,
      formUrl: formUrl,
      editUrl: editUrl,
      directEditUrl: editUrl,
      sharedWith: userEmail || null,
      editorAdded: editorAdded,
      editorsAdded: editorsAdded,
      editorsFailed: editorsFailed,
      sharingMode: sharingSet ? 'anyone_with_link_can_edit' : 'restricted',
      linkSharingEnabled: sharingSet,
      timestamp: new Date().toISOString(),
      message: editorAdded || sharingSet ? 'Success' : 'Form created but no edit permissions'
    };

    console.log('Final response:', JSON.stringify(response));
    return ContentService.createTextOutput(JSON.stringify(response))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    console.error('Error at stage:', response.stage);
    console.error('Error:', error.toString());

    // フォームが作成された場合は部分的な成功として返す
    if (formId) {
      response.success = true;
      response.formId = formId;
      response.formUrl = formUrl || '';
      response.editUrl = editUrl || '';
      response.error = error.toString();
      response.errorStage = response.stage;
    } else {
      response.success = false;
      response.error = error.toString();
    }

    return ContentService.createTextOutput(JSON.stringify(response))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// テスト関数
function test() {
  const testData = {
    postData: {
      contents: JSON.stringify({
        action: 'createForm',
        userEmail: 'yudai71015@gmail.com',
        firebaseEmail: 'yudai5287@ruri.waseda.jp',
        template: {
          title: 'Test Form',
          description: 'Test',
          questions: []
        }
      })
    }
  };

  const result = doPost(testData);
  console.log('Test result:', result.getContent());
}