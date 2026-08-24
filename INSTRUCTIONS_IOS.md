# How to Build and Run on iPhone 15 (From Windows without a Mac)

This folder (`flood-assistant-ios`) has been configured so you can build and run this Flutter app on your **iPhone 15** directly from **Windows** using **GitHub Actions** (free cloud Mac) and **Sideloadly**.

---

## Step 1: Push `flood-assistant-ios` to GitHub

1. Open your terminal in this folder (`flood-assistant-ios`).
2. Initialize Git if not already done, commit, and push to GitHub:
   ```bash
   git init
   git add .
   git commit -m "Configure iOS build workflow and privacy permissions"
   git branch -M main
   git remote add origin https://github.com/YOUR_GITHUB_USERNAME/flood-assistant-ios.git
   git push -u origin main
   ```

---

## Step 2: Download `Runner.ipa` from GitHub Actions

1. Go to your repository page on **GitHub.com**.
2. Click on the **Actions** tab at the top.
3. Select the latest **Build iOS App (.ipa)** workflow run (takes ~4-5 minutes).
4. Scroll down to the **Artifacts** section at the bottom.
5. Click **iPhone15-App-Runner** to download the `Runner.ipa` zip file to your Windows PC.
6. Extract the downloaded zip file to get `Runner.ipa`.

---

## Step 3: Enable Developer Mode on your iPhone 15

1. On your iPhone 15, go to **Settings** > **Privacy & Security**.
2. Scroll to the very bottom and tap **Developer Mode**.
3. Toggle **Developer Mode ON** and restart your iPhone 15 when prompted.
4. After restarting, unlock your phone, tap **Turn On**, and enter your passcode.

---

## Step 4: Install onto iPhone 15 using Sideloadly (from Windows)

1. Download & Install **[Sideloadly](https://sideloadly.io/)** on your Windows PC.
2. Connect your **iPhone 15** to your Windows PC using a USB-C cable.
3. Open **Sideloadly**:
   - Ensure your iPhone 15 appears in the **Device** box.
   - Drag and drop `Runner.ipa` into the IPA icon box in Sideloadly.
   - Enter your **Apple ID** in the Apple ID field.
   - Click **Start**.
4. Sideloadly will sign the app and install it onto your iPhone 15.

---

## Step 5: Trust App Profile on iPhone 15

1. On your iPhone 15, open **Settings** > **General** > **VPN & Device Management**.
2. Tap your Apple ID email under **Developer App**.
3. Tap **Trust [Your Email]** and confirm.
4. Return to your home screen and open **Flood Assistant**!

---

## Alternative: Instant Web Test on iPhone 15 (No Cable / No Installation)

If you want to quickly test the app on your iPhone 15 browser right now:
1. On Windows, build the web version:
   ```bash
   flutter build web
   ```
2. Upload `build/web` to free hosting like [Vercel](https://vercel.com) or [Netlify](https://netlify.com).
3. Open the link on iPhone 15 Safari > tap **Share** > **Add to Home Screen**.
