// Google Apps Script - Forms API Web App with Sharing
// このスクリプトをGoogle Apps Scriptにデプロイして使用します
// 改善版：作成したフォームに指定されたユーザーを編集者として追加

function doPost(e) {
  try {
    // CORS対応ヘッダーを含むレスポンスを作成する関数
    function createResponse(content) {
      const output = ContentService.createTextOutput(JSON.stringify(content));
      output.setMimeType(ContentService.MimeType.JSON);
      return output;
    }

    console.log('Received POST request');
    console.log('Headers:', JSON.stringify(e.headers || {}));
    console.log('User-Agent:', e.parameter['User-Agent'] || 'Unknown');
    console.log('Raw post data:', e.postData.contents);

    const data = JSON.parse(e.postData.contents);
    const action = data.action;

    console.log('Parsed data action:', action);
    console.log('Data userEmail:', data.userEmail);
    console.log('Data firebaseEmail:', data.firebaseEmail);

    if (action === 'createForm') {
      return createFormFromTemplate(data);
    } else if (action === 'shareForm') {
      return shareFormWithUser(data);
    } else {
      return createResponse({
        success: false,
        error: 'Invalid action'
      });
    }
  } catch (error) {
    console.error('doPost error:', error.toString());
    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: error.toString(),
      stack: error.stack || 'No stack trace'
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

// GETリクエストにも対応（CORSプリフライト用）
function doGet(e) {
  const output = ContentService.createTextOutput(JSON.stringify({
    success: true,
    message: 'Google Forms API is ready',
    version: '1.1'
  }));
  output.setMimeType(ContentService.MimeType.JSON);
  return output;
}

function createFormFromTemplate(data) {
  // 変数を関数スコープの最初で宣言
  let form;
  let formId;
  let formUrl;
  let editUrl;
  let userEditUrl;
  let sharingSet = false;
  let editorAdded = false;
  let editorsAdded = [];
  let editorsFailed = [];

  try {
    console.log('createFormFromTemplate called');
    console.log('Full data received:', JSON.stringify(data));
    const template = data.template;
    const customTitle = data.customTitle || template.title;

    // メールアドレスを確実に取得（template内にある可能性も考慮）
    let userEmail = data.userEmail || (template && template.userEmail) || null;
    let firebaseEmail = data.firebaseEmail || (template && template.firebaseEmail) || null;

    console.log('Creating form with title:', customTitle);
    console.log('Extracted userEmail:', userEmail);
    console.log('Extracted firebaseEmail:', firebaseEmail);

    // デバッグ: データ構造を詳細に確認
    console.log('Data structure check:');
    console.log('- data.userEmail:', data.userEmail);
    console.log('- data.firebaseEmail:', data.firebaseEmail);
    console.log('- template.userEmail:', template ? template.userEmail : 'template is null');
    console.log('- typeof data:', typeof data);
    console.log('- data keys:', Object.keys(data));
    console.log('- template keys:', template ? Object.keys(template) : 'template is null');

    // Google Formを作成
    try {
      form = FormApp.create(customTitle);
      console.log('Form created successfully with ID:', form.getId());
    } catch (formError) {
      console.error('Failed to create form:', formError.toString());
      throw new Error('フォームの作成に失敗しました: ' + formError.toString());
    }

    // フォームの説明を設定
    if (template.description || template.instructions) {
      const fullDescription = [
        template.description,
        template.instructions
      ].filter(Boolean).join('\n\n');
      form.setDescription(fullDescription);
    }

    // 質問を追加
    console.log('Adding', template.questions.length, 'questions');
    template.questions.forEach((question, index) => {
      try {
        addQuestionToForm(form, question);
        console.log('Added question', (index + 1), ':', question.question);
      } catch (qError) {
        console.error('Failed to add question', (index + 1), ':', qError.toString());
      }
    });

    // フォームの共有設定を変更（リンクを知っている全員が編雈可能）
    form.setRequireLogin(false);
    form.setCollectEmail(true); // メールアドレスを収集するように変更
    form.setLimitOneResponsePerUser(false);
    form.setShowLinkToRespondAgain(true);

    console.log('Form basic settings configured');
    console.log('Form ID:', form.getId());
    console.log('Form owner will be:', Session.getActiveUser().getEmail());

    // フォームの情報を取得
    formId = form.getId();
    formUrl = form.getPublishedUrl();
    editUrl = form.getEditUrl();

    // フォームのファイルIDを取得
    const formFile = DriveApp.getFileById(formId);

    // ファイルの共有設定を「リンクを知っている全員が編集可能」に設定
    try {
      // まず現在の共有設定を確認
      console.log('Current sharing access:', formFile.getSharingAccess());
      console.log('Current sharing permission:', formFile.getSharingPermission());

      // 共有設定を変更
      formFile.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.EDIT);

      // 設定後の確認
      console.log('After setSharing - access:', formFile.getSharingAccess());
      console.log('After setSharing - permission:', formFile.getSharingPermission());
      console.log('Successfully set form to be editable by anyone with link');
      sharingSet = true;
    } catch (sharingError) {
      console.error('Failed to set sharing settings: ' + sharingError.toString());
      console.error('Error details:', sharingError.stack || 'No stack trace');
      // エラーが発生しても続行
    }

    // 複数のメールアドレスに編集権限を付与
    const emailsToAdd = [];

    console.log('=== Starting editor permission process ===');
    console.log('Raw userEmail value:', userEmail);
    console.log('Raw firebaseEmail value:', firebaseEmail);
    console.log('Type of userEmail:', typeof userEmail);
    console.log('Type of firebaseEmail:', typeof firebaseEmail);

    // デバッグ：data全体の構造も確認
    console.log('Checking data structure:');
    console.log('data.userEmail:', data.userEmail);
    console.log('data.firebaseEmail:', data.firebaseEmail);
    if (data.template) {
      console.log('data.template.userEmail:', data.template.userEmail);
    }

    // 上で既に取得したuserEmailとfirebaseEmailを使用
    if (userEmail && typeof userEmail === 'string' && userEmail.includes('@')) {
      console.log('Primary email to add (Google Account from settings):', userEmail);
      emailsToAdd.push(userEmail);
    } else {
      console.log('No valid userEmail found. Value:', userEmail);
    }

    // Firebase Authのメールアドレスも追加（異なる場合）
    if (firebaseEmail && typeof firebaseEmail === 'string' &&
        firebaseEmail.includes('@') && firebaseEmail !== userEmail) {
      console.log('Secondary email to add (Firebase Auth):', firebaseEmail);
      emailsToAdd.push(firebaseEmail);
    } else {
      console.log('No valid firebaseEmail or same as userEmail:', firebaseEmail);
    }

    console.log('Total emails to add as editors:', emailsToAdd.length);
    console.log('Emails to add as editors: ' + (emailsToAdd.length > 0 ? emailsToAdd.join(', ') : 'None'));

    // すべてのメールアドレスに編雈権限を付与
    for (const email of emailsToAdd) {
      console.log('Processing email: ' + email);
      let addedForThisEmail = false;
      for (let attempt = 1; attempt <= 3; attempt++) {
        try {
          // メールアドレスの検証
          if (!email || !email.includes('@') || email.includes(' ')) {
            console.error('Invalid email format: ' + email);
            editorsFailed.push({email: email, reason: 'Invalid format'});
            break;
          }

          // 編集者として追加
          formFile.addEditor(email);
          console.log('Successfully added editor: ' + email + ' (attempt ' + attempt + ')');

          // 確認のために少し待機
          Utilities.sleep(500);

          // 編集者として追加されたことを確認
          const editors = formFile.getEditors();
          const isEditor = editors.some(editor => {
            const editorEmail = editor.getEmail();
            return editorEmail && editorEmail.toLowerCase() === email.toLowerCase();
          });

          if (isEditor) {
            console.log('Confirmed: ' + email + ' is now an editor');
            editorsAdded.push(email);
            editorAdded = true;
            addedForThisEmail = true;
          } else {
            console.log('Warning: ' + email + ' was not found in editors list after adding');
            if (sharingSet) {
              console.log('But form is set to "Anyone with link can edit", so user can still edit');
              editorsAdded.push(email + ' (via link)');
              editorAdded = true;
              addedForThisEmail = true;
            }
          }
          break;
        } catch (shareError) {
          console.error('Attempt ' + attempt + ' failed to add editor ' + email + ': ' + shareError.toString());

          if (shareError.toString().includes('Invalid email') ||
              shareError.toString().includes('does not exist')) {
            console.error('Email address may not be a valid Google account: ' + email);
            editorsFailed.push({email: email, reason: shareError.toString()});
            break; // 無効なメールの場合はリトライしない
          }

          if (attempt < 3) {
            console.log('Retrying in 1 second...');
            Utilities.sleep(1000); // 1秒待機して再試行
          } else {
            editorsFailed.push({email: email, reason: shareError.toString()});
          }
        }
      }

      if (!addedForThisEmail && sharingSet) {
        console.log(email + ' could not be added as editor, but can still edit via link sharing');
      }
    }

    // ユーザー専用の編集URLを生成
    // 連携したGoogleアカウントを優先（emailsToAddの最初の要素を使用）
    const targetEmail = emailsToAdd.length > 0 ? emailsToAdd[0] : (userEmail || firebaseEmail);
    userEditUrl = editUrl;
    if (targetEmail && targetEmail.includes('@')) {
      // authuserパラメータとlogin_hintを追加
      const urlObj = new URL(editUrl);
      // アカウント切り替えを促すパラメータ
      urlObj.searchParams.set('authuser', '0'); // デフォルトアカウントを指定
      urlObj.searchParams.set('login_hint', targetEmail);
      urlObj.searchParams.set('hd', targetEmail.split('@')[1]); // ドメインヒント
      userEditUrl = urlObj.toString();

      console.log('Generated edit URL for user:', targetEmail);
      console.log('Edit URL:', userEditUrl);
    }

    // 最終的な編集権限の状態をログ出力
    console.log('=== Final Editor Status ===');
    console.log('Form owner:', Session.getActiveUser().getEmail());
    console.log('Requested editors:', emailsToAdd.join(', '));
    console.log('Editors successfully added: ' + editorsAdded.join(', '));
    if (editorsFailed.length > 0) {
      console.log('Failed to add editors: ' + JSON.stringify(editorsFailed));
    }
    console.log('Link sharing enabled: ' + sharingSet);
    console.log('Target user should access with:', userEmail || firebaseEmail || 'No email');
    console.log('===========================');

    // レスポンスオブジェクトを作成（すべてのフィールドを明示的に設定）
    const response = {
      success: true,
      formId: formId || '',
      formUrl: formUrl || '',
      editUrl: userEditUrl || editUrl || '',
      directEditUrl: editUrl || '',
      sharedWith: emailsToAdd.length > 0 ? emailsToAdd[0] : null,
      editorAdded: Boolean(editorAdded),
      editorsAdded: editorsAdded || [],
      editorsFailed: editorsFailed || [],
      sharingMode: sharingSet ? 'anyone_with_link_can_edit' : 'restricted',
      linkSharingEnabled: Boolean(sharingSet),
      timestamp: new Date().toISOString(),
      message: (editorAdded || sharingSet)
        ? 'フォームが作成され、編集権限が設定されました'
        : 'フォームは作成されましたが、編集権限の設定に失敗しました',
      instruction: 'フォームを開く際は、' + (userEmail || firebaseEmail || '連携した') + ' Googleアカウントでログインしてください'
    };

    console.log('Returning success response:', JSON.stringify(response));
    return ContentService.createTextOutput(JSON.stringify(response))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    console.error('createFormFromTemplate error:', error.toString());
    console.error('Stack trace:', error.stack);
    console.error('Error occurred at stage:', error.stage || 'unknown');

    // 部分的に成功した場合のレスポンス
    if (typeof formId !== 'undefined' && formId) {
      const partialResponse = {
        success: true,  // フォームは作成されたので成功扱い
        formId: formId,
        formUrl: typeof formUrl !== 'undefined' ? formUrl : '',
        editUrl: typeof editUrl !== 'undefined' ? editUrl : '',
        directEditUrl: typeof editUrl !== 'undefined' ? editUrl : '',
        sharedWith: null,
        editorAdded: false,
        editorsAdded: [],
        editorsFailed: [],
        sharingMode: 'unknown',
        linkSharingEnabled: false,
        timestamp: new Date().toISOString(),
        message: 'フォームは作成されましたが、編集権限の設定でエラーが発生しました: ' + error.toString(),
        error: error.toString()
      };

      console.log('Returning partial success response:', JSON.stringify(partialResponse));
      return ContentService.createTextOutput(JSON.stringify(partialResponse))
        .setMimeType(ContentService.MimeType.JSON);
    }

    const errorResponse = {
      success: false,
      error: error.toString(),
      details: 'Form creation failed in Google Apps Script',
      stack: error.stack || 'No stack trace',
      timestamp: new Date().toISOString()
    };

    return ContentService.createTextOutput(JSON.stringify(errorResponse))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// 既存のフォームに編集者を追加する関数
function shareFormWithUser(data) {
  try {
    const formId = data.formId;
    const userEmail = data.userEmail;

    if (!formId || !userEmail) {
      throw new Error('formId and userEmail are required');
    }

    const formFile = DriveApp.getFileById(formId);
    formFile.addEditor(userEmail);

    return ContentService.createTextOutput(JSON.stringify({
      success: true,
      message: 'Form shared successfully',
      formId: formId,
      sharedWith: userEmail
    })).setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: error.toString()
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

function addQuestionToForm(form, question) {
  let item;

  switch (question.type) {
    case 'multipleChoice':
      item = form.addMultipleChoiceItem();
      item.setTitle(question.question);
      if (question.options) {
        item.setChoiceValues(question.options);
      }
      break;

    case 'checkbox':
      item = form.addCheckboxItem();
      item.setTitle(question.question);
      if (question.options) {
        item.setChoiceValues(question.options);
      }
      break;

    case 'scale':
      item = form.addScaleItem();
      item.setTitle(question.question);
      item.setBounds(question.scaleMin || 1, question.scaleMax || 5);
      if (question.scaleMinLabel) {
        item.setLabels(question.scaleMinLabel, question.scaleMaxLabel || '');
      }
      break;

    case 'shortText':
      item = form.addTextItem();
      item.setTitle(question.question);
      break;

    case 'longText':
      item = form.addParagraphTextItem();
      item.setTitle(question.question);
      break;

    case 'date':
      item = form.addDateItem();
      item.setTitle(question.question);
      break;

    case 'time':
      item = form.addTimeItem();
      item.setTitle(question.question);
      break;

    default:
      item = form.addTextItem();
      item.setTitle(question.question);
  }

  // 必須設定
  if (item && question.required) {
    item.setRequired(true);
  }

  // プレースホルダー（ヘルプテキスト）設定
  if (item && question.placeholder) {
    item.setHelpText(question.placeholder);
  }
}

// テスト用関数
function test() {
  const testData = {
    action: 'createForm',
    template: {
      title: 'テストフォーム',
      description: 'これはテストフォームです',
      questions: [
        {
          question: '名前を入力してください',
          type: 'shortText',
          required: true
        },
        {
          question: '満足度を評価してください',
          type: 'scale',
          required: true,
          scaleMin: 1,
          scaleMax: 5,
          scaleMinLabel: '不満',
          scaleMaxLabel: '満足'
        }
      ]
    },
    userEmail: 'test@example.com' // テスト用メールアドレス
  };

  const result = createFormFromTemplate(testData);
  console.log(result.getContent());
}