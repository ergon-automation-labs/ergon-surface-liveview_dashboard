pipeline {
  // Deploy Phoenix LiveView surface: download release from GitHub, deploy, restart (same pattern as bots).
  agent { label 'built-in' }

  options {
    timeout(time: 30, unit: 'MINUTES')
    timestamps()
  }

  triggers {
    pollSCM('H/5 * * * *')
  }

  environment {
    SURFACE_NAME = 'bot_army_dashboard_liveview'
    SURFACE_PORT = '30011'
    RELEASE_DIR = "/opt/ergon/releases/${SURFACE_NAME}"
    GITHUB_REPO = "ergon-automation-labs/bot-army-dashboard-liveview"
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Download Build Artifact') {
      steps {
        sh '''
          echo "==============================================="
          echo "Downloading pre-built release from GitHub"
          echo "==============================================="

          LATEST_RELEASE=$(gh api repos/${GITHUB_REPO}/releases \
            -q '.[] | select(.draft==false) | .tag_name' | head -1)

          if [ -z "$LATEST_RELEASE" ]; then
            echo "ERROR: No published release found on GitHub for ${GITHUB_REPO}"
            exit 1
          fi

          echo "Latest release: $LATEST_RELEASE"
          mkdir -p ./release-artifact

          gh release download $LATEST_RELEASE \
            --repo ${GITHUB_REPO} \
            --pattern "*.tar.gz" \
            -D ./release-artifact

          echo "✓ Release downloaded successfully"

          cd ./release-artifact
          TARBALL=$(ls -1 *.tar.gz 2>/dev/null | head -1)
          if [ -z "$TARBALL" ]; then
            echo "ERROR: No .tar.gz asset in release"
            exit 1
          fi
          echo "Extracting: $TARBALL"
          tar -xzf "$TARBALL"
          rm "$TARBALL"
          ls -la
          cd ..
        '''
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          echo "==============================================="
          echo "Deploying surface ${SURFACE_NAME} (port ${SURFACE_PORT})"
          echo "==============================================="
          echo "Start time: $(date)"

          TIMESTAMP=$(date +%Y%m%d%H%M%S)
          DEST="${RELEASE_DIR}/releases/${TIMESTAMP}"

          echo "Creating release directory..."
          mkdir -p "${DEST}"

          echo "Copying release artifacts..."
          cp -r ./release-artifact/* "${DEST}/"

          echo "Updating current symlink..."
          ln -sfn "${DEST}" "${RELEASE_DIR}/current"

          echo "Restarting service..."
          launchctl kickstart -k system/com.botarmy.${SURFACE_NAME} 2>/dev/null || \
            launchctl load /Library/LaunchDaemons/com.botarmy.${SURFACE_NAME}.plist 2>/dev/null || true

          echo "Waiting for service to stabilize..."
          sleep 5

          echo "Deploy complete!"
          echo "Completion time: $(date)"
        '''
      }
    }

  }

  post {
    success {
      sh '''
        echo "📢 Surface ${SURFACE_NAME} deployed (port ${SURFACE_PORT})"
      '''
    }
    failure {
      sh '''
        echo "Surface ${SURFACE_NAME} deployment failed"
      '''
    }
    always {
      cleanWs()
    }
  }
}
