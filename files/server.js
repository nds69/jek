// required packages: express multer @octokit/rest dotenv
require('dotenv').config(); 
const express = require('express');
const multer = require('multer');
const { Octokit } = require('@octokit/rest');
const upload = multer(); 
const app = express();
const port = process.env.SERVER_PORT || 3000;

// GitHub Configuration from .env
const GITHUB_TOKEN = process.env.GITHUB_TOKEN; 
const REPO_OWNER = process.env.REPO_OWNER; 
const REPO_NAME = process.env.REPO_NAME;    
const BRANCH_NAME = process.env.BRANCH_NAME; 
const COUNTER_FILE_PATH = process.env.COUNTER_FILE_PATH || 'upload_count.json';

const octokit = new Octokit({ auth: GITHUB_TOKEN });

// CORS (Cross-Origin Resource Sharing) ကို ခွင့်ပြုရန်
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*'); 
    res.header('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type');
    next();
});

// Counter Update Logic (Server-side)
async function incrementCounter() {
    const apiUrl = `repos/${REPO_OWNER}/${REPO_NAME}/contents/${COUNTER_FILE_PATH}`;

    let currentSha = null;
    let currentCount = 0;
    
    // 1. Get current counter content and SHA
    try {
        const { data: getResponse } = await octokit.request('GET /' + apiUrl);
        currentSha = getResponse.sha;
        const content = Buffer.from(getResponse.content, 'base64').toString('utf8');
        try {
            const jsonContent = JSON.parse(content);
            currentCount = jsonContent.count || 0;
        } catch (parseError) {
            console.warn('Could not parse existing counter JSON. Starting count from 0.');
            currentCount = 0;
        }
    } catch (e) { 
        if (e.status !== 404) {
             console.error('Error fetching counter:', e.message);
             return; 
        }
        // 404 means file not found, count remains 0
    }
    
    // 2. Prepare new content
    const newCount = currentCount + 1;
    const newContentJson = { count: newCount };
    const newContentString = JSON.stringify(newContentJson, null, 2); 
    const newBase64Content = Buffer.from(newContentString).toString('base64');

    // 3. Commit new content
    const commitMessage = `Auto-increment counter to ${newCount}`;
    const putData = { 
        message: commitMessage, 
        content: newBase64Content, 
        sha: currentSha, 
        branch: BRANCH_NAME 
    };

    try {
        await octokit.request('PUT /' + apiUrl, putData);
        console.log(`Counter updated to: ${newCount}`);
    } catch (e) {
        console.error(`Counter Update Failed: ${e.message}`);
    }
}


// ⚠️ File Upload Endpoint ⚠️
app.post('/api/upload', upload.single('file'), async (req, res) => {
    if (!GITHUB_TOKEN) {
        return res.status(500).json({ message: 'Server error: GITHUB_TOKEN not set.' });
    }
    if (!req.file) {
        return res.status(400).json({ message: 'No file uploaded.' });
    }

    const file = req.file;
    const repoPath = req.body.repoPath ? req.body.repoPath.replace(/^\/+/, '') : `files/${file.originalname}`; 
    const base64Content = file.buffer.toString('base64');
    
    let existingSha = null;
    let isUpdate = false;

    try {
        // 1. Get existing file SHA (if any)
        try {
            const { data } = await octokit.rest.repos.getContent({
                owner: REPO_OWNER,
                repo: REPO_NAME,
                path: repoPath,
                ref: BRANCH_NAME,
            });
            existingSha = data.sha;
            isUpdate = true;
        } catch (error) {
            if (error.status !== 404) { throw error; } 
        }

        // 2. Upload/Update the file
        const action = isUpdate ? 'Update' : 'Create';
        const commitMessage = `${action}: ${file.originalname} (${new Date().toLocaleTimeString()})`;
        
        const uploadResponse = await octokit.rest.repos.createOrUpdateFileContents({
            owner: REPO_OWNER,
            repo: REPO_NAME,
            path: repoPath,
            message: commitMessage,
            content: base64Content,
            sha: existingSha, 
            branch: BRANCH_NAME,
        });
        
        // 3. Increment Counter - ဤအဆင့်သည် ကောင်တာကို update လုပ်ပေးမည်
        await incrementCounter(); 

        // Client ကို ပြန်ပို့မည့် URL
        res.status(200).json({ 
            message: isUpdate ? 'ဖိုင်အား အောင်မြင်စွာ အပ်ဒိတ်လုပ်ပြီးပါပြီ' : 'ဖိုင်အသစ်အား အောင်မြင်စွာ Upload လုပ်ပြီးပါပြီ',
            content_url: uploadResponse.data.content.html_url,
            raw_url_path: uploadResponse.data.content.path 
        });

    } catch (error) {
        console.error('GitHub API Error:', error);
        res.status(500).json({ 
            message: 'Upload Failed due to GitHub API or Server Error', 
            error: error.message || 'Unknown Server Error' 
        });
    }
});

app.listen(port, () => {
    console.log(`GitHub Uploader API listening on port ${port}`);
});
