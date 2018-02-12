#!groovy

if ("$SKIP_BUILD" == "true") {
  stage "Config credentials"
  println("Skipping as per user request")
  stage "Tagging"
  println("Skipping as per user request")
  stage "Building"
  println("Skipping as per user request")
}
else {
  node ("$BUILD_ARCH-$MESOS_QUEUE_SIZE") {

    stage "Config credentials"
    withCredentials([[$class: 'UsernamePasswordMultiBinding',
                      credentialsId: 'github_alibuild',
                      usernameVariable: 'GIT_BOT_USER',
                      passwordVariable: 'GIT_BOT_PASS']]) {
      sh '''
        set -e
        set -o pipefail
        printf "protocol=https\nhost=github.com\nusername=$GIT_BOT_USER\npassword=$GIT_BOT_PASS\n" | \
          git credential-store --file "$PWD/git-creds" store
      '''
    }
    withCredentials([[$class: 'UsernamePasswordMultiBinding',
                      credentialsId: 'gitlab_alibuild',
                      usernameVariable: 'GIT_BOT_USER',
                      passwordVariable: 'GIT_BOT_PASS']]) {
      sh '''
        set -e
        set -o pipefail
        printf "protocol=https\nhost=gitlab.cern.ch\nusername=$GIT_BOT_USER\npassword=$GIT_BOT_PASS\n" | \
          git credential-store --file "$PWD/git-creds" store
      '''
    }
    sh '''
      set -e
      set -o pipefail
      git config --global credential.helper "store --file $PWD/git-creds"
    '''

    stage "Tagging"
    withEnv(["TAGS=$TAGS",
             "ALIDIST=$ALIDIST"]) {
      sh '''
        set -e
        set -o pipefail
        ALIDIST_BRANCH="${ALIDIST##*:}"
        ALIDIST_REPO="${ALIDIST%:*}"
        [[ $ALIDIST_BRANCH == $ALIDIST ]] && ALIDIST_BRANCH= || true
        rm -rf alidist
        git clone ${ALIDIST_BRANCH:+-b "$ALIDIST_BRANCH"} "https://github.com/$ALIDIST_REPO" alidist/ || \
          { git clone "https://github.com/$ALIDIST_REPO" alidist/ && pushd alidist && git checkout "$ALIDIST_BRANCH" && popd; }
        for TAG in $TAGS; do
          VER="${TAG##*=}"
          PKG="${TAG%=*}"
          PKGLOW="$(echo "$PKG"|tr '[:upper:]' '[:lower:]')"
          REPO=$(cat alidist/"$PKGLOW".sh | grep '^source:' | head -n1)
          REPO=${REPO#*:}
          REPO=$(echo $REPO)
          sed -e "s/tag:.*/tag: $VER/" "alidist/$PKGLOW.sh" > "alidist/$PKGLOW.sh.0"
          mv "alidist/$PKGLOW.sh.0" "alidist/$PKGLOW.sh"
          git ls-remote --tags "$REPO" | grep "refs/tags/$VER\\$" && { echo "Tag $VER on $PKG exists - skipping"; continue; } || true
          rm -rf "$PKG/"
          git clone $([[ -d /build/mirror/$PKGLOW ]] && echo "--reference /build/mirror/$PKGLOW") "$REPO" "$PKG/"
          pushd "$PKG/"
            if [[ $PKG == AliDPG ]]; then
              DPGBRANCH="${VER%-XX-*}"
              [[ $DPGBRANCH != $VER ]] || { echo "Cannot determine AliDPG branch to tag from $VER - aborting"; exit 1; }
              DPGBRANCH="${DPGBRANCH}-XX"
              git checkout "$DPGBRANCH"
            fi
            git tag "$VER"
            git push origin "$VER"
          popd
          rm -rf "$PKG/"
        done
      '''
    }

    stage "Building"
    withEnv(["TAGS=$TAGS",
             "BUILD_ARCH=$BUILD_ARCH",
             "DEFAULTS=$DEFAULTS",
             "ALIBUILD=$ALIBUILD"]) {
      sh '''
        set -e
        set -o pipefail

        # aliBuild installation using pip
        ALIBUILD_BRANCH="${ALIBUILD##*:}"
        ALIBUILD_REPO="${ALIBUILD%:*}"
        [[ $ALIBUILD_BRANCH == $ALIBUILD ]] && ALIBUILD_BRANCH= || true
        export PYTHONUSERBASE="$PWD/python"
        export PATH="$PYTHONUSERBASE/bin:$PATH"
        rm -rf "$PYTHONUSERBASE"
        pip install --user "git+https://github.com/$ALIBUILD_REPO${ALIBUILD_BRANCH:+"@$ALIBUILD_BRANCH"}"
        which aliBuild

        # Prepare scratch directory
        BUILD_DATE=$(echo 2015$(echo "$(date -u +%s) / (86400 * 3)" | bc))
        WORKAREA=/build/workarea/sw/$BUILD_DATE
        WORKAREA_INDEX=0
        CURRENT_SLAVE=unknown
        while [[ "$CURRENT_SLAVE" != '' ]]; do
          WORKAREA_INDEX=$((WORKAREA_INDEX+1))
          CURRENT_SLAVE=$(cat $WORKAREA/$WORKAREA_INDEX/current_slave 2> /dev/null || true)
          [[ "$CURRENT_SLAVE" == "$NODE_NAME" ]] && CURRENT_SLAVE=
        done
        mkdir -p $WORKAREA/$WORKAREA_INDEX
        echo $NODE_NAME > $WORKAREA/$WORKAREA_INDEX/current_slave

        # Actual build of all packages from TAGS
        FETCH_REPOS="$(aliBuild build --help | grep fetch-repos || true)"
        for PKG in $TAGS; do
          BUILDERR=
          aliBuild --reference-sources /build/mirror                       \
                   --debug                                                 \
                   --work-dir "$WORKAREA/$WORKAREA_INDEX"                  \
                   --architecture "$BUILD_ARCH"                            \
                   ${FETCH_REPOS:+--fetch-repos}                           \
                   --jobs 16                                               \
                   --remote-store "rsync://repo.marathon.mesos/store/::rw" \
                   ${DEFAULTS:+--defaults "$DEFAULTS"}                     \
                   build "${PKG%%=*}" || BUILDERR=$?
          [[ $BUILDERR ]] && break || true
        done
        rm -f "$WORKAREA/$WORKAREA_INDEX/current_slave"
        [[ "$BUILDERR" ]] && exit $BUILDERR || true
      '''
    }

  }
}

node("$RUN_ARCH-relval") {

  stage "Waiting for deployment"
  withEnv(["TAGS=$TAGS",
           "CVMFS_NAMESPACE=$CVMFS_NAMESPACE"]) {
    sh '''
      set -e
      set -o pipefail

      MAIN_PKG="${TAGS%%=*}"
      MAIN_VER=$(echo "$TAGS"|cut -d' ' -f1)
      MAIN_VER="${MAIN_VER#*=}"

      SW_COUNT=0
      SW_MAXCOUNT=1200
      CVMFS_SIGNAL="/tmp/${CVMFS_NAMESPACE}.cern.ch.cvmfs_reload /build/workarea/wq/${CVMFS_NAMESPACE}.cern.ch.cvmfs_reload"
      mkdir -p /build/workarea/wq || true
      while [[ $SW_COUNT -lt $SW_MAXCOUNT ]]; do
        ALL_FOUND=1
        for PKG in $TAGS; do
          /cvmfs/${CVMFS_NAMESPACE}.cern.ch/bin/alienv q | \
            grep -E VO_ALICE@"${PKG%%=*}"::"${PKG#*=}" || { ALL_FOUND= ; break; }
        done
        [[ $ALL_FOUND ]] && { echo "All packages ($TAGS) published"; break; } || true
        for S in $CVMFS_SIGNAL; do
          [[ -e $S ]] && true || touch $S
        done
        sleep 1
        SW_COUNT=$((SW_COUNT+1))
      done
      [[ $ALL_FOUND ]] && true || { "Timeout while waiting for packages to be published"; exit 1; }
    '''
  }

  stage "Checking framework"
  if ("$SKIP_CHECK_FRAMEWORK" == "true") {
    println("Skipping as per user request")
  }
  else {
    sh '''
      set -e
      set -o pipefail
      curl -X DELETE -H "Content-type: application/json" "http://leader.mesos:8080/v2/apps/wqmesos/tasks?scale=true"
      curl -X DELETE -H "Content-type: application/json" "http://leader.mesos:8080/v2/apps/wqcatalog/tasks?scale=true"
      curl -X PUT -H "Content-type: application/json" --data '{ "instances": 1 }' "http://leader.mesos:8080/v2/apps/wqcatalog?force=true"
      sleep 90
      curl -X PUT -H "Content-type: application/json" --data '{ "instances": 1 }' "http://leader.mesos:8080/v2/apps/wqmesos?force=true"
    '''
  }

  stage "Validating"
  withEnv(["LIMIT_FILES=$LIMIT_FILES",
           "LIMIT_EVENTS=$LIMIT_EVENTS",
           "CVMFS_NAMESPACE=$CVMFS_NAMESPACE",
           "DATASET=$DATASET",
           "MONKEYPATCH_TARBALL_URL=$MONKEYPATCH_TARBALL_URL",
           "REQUIRED_SPACE_GB=$REQUIRED_SPACE_GB",
           "REQUIRED_FILES=$REQUIRED_FILES",
           "JIRA_ISSUE=$JIRA_ISSUE",
           "RELVAL_TIMESTAMP=$RELVAL_TIMESTAMP",
           "TAGS=$TAGS"]) {
    withCredentials([[$class: 'UsernamePasswordMultiBinding',
                      credentialsId: '369b09bf-5f5e-4b68-832a-2f30cad28755',
                      usernameVariable: 'JIRA_USER',
                      passwordVariable: 'JIRA_PASS']]) {
      sh '''
        set -e
        set -o pipefail

        echo TESTING, STOP NOW
        exit 0

        MAIN_PKG="${TAGS%%=*}"
        [[ $MAIN_PKG == AliPhysics ]]
        MAIN_VER=$(echo "$TAGS"|cut -d' ' -f1)
        MAIN_VER="${MAIN_VER#*=}"
        ALIPHYSICS_VERSION=$(/cvmfs/${CVMFS_NAMESPACE}.cern.ch/bin/alienv q | grep -E VO_ALICE@"$MAIN_PKG"::"$MAIN_VER"-'[0-9]$' | sort -V | tail -n1)
        export ALIPHYSICS_VERSION="${ALIPHYSICS_VERSION##*:}"
        [[ $ALIPHYSICS_VERSION ]]

        RELVAL_BRANCH="${RELVAL##*:}"
        RELVAL_REPO="${RELVAL%:*}"
        [[ $RELVAL_BRANCH == $RELVAL ]] && RELVAL_BRANCH= || true
        rm -rf release-validation/
        git clone "https://github.com/$RELVAL_REPO" ${RELVAL_BRANCH:+-b "$RELVAL_BRANCH"} release-validation/

        if [[ $RUN_MC_VALIDATION == true ]]; then
          # Prerequisite (workaround)
          yum install -y libxslt-devel

          # Run AliDPG-based Monte Carlo validation based on examples
          RELVAL_NAME="MC-AliPhysics-${ALIPHYSICS_VERSION}-${RELVAL_TIMESTAMP}"
          export PYTHONUSERBASE=$PWD/python
          export PATH=$PYTHONUSERBASE/bin:$PATH
          rm -rf python && mkdir python
          pip install --user release-validation/mc

          # Use an example and modify it
          sed -e "s/gpmc001/$RELVAL_NAME/" "release-validation/mc/examples/gpmc_LHC17m/"*.jdl > mcval.jdl
          cat mcval.jdl

          # Credentials and Config.cfg
          cp -v /secrets/eos-proxy .
          cp -v release-validation/mc/examples/gpmc_LHC17m/Custom.cfg .

          # Run it right away
          jdl2makeflow --force --run mcval.jdl -T wq -N alirelval_${RELVAL_NAME} -r 3 -C wqcatalog.marathon.mesos:9097
        else
          echo "We will be using AliPhysics $ALIPHYSICS_VERSION with the following environment"
          env
          release-validation/relval-jenkins.sh
        fi
      '''
    }
  }
}
