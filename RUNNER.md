This macOS GitHub Actions runner is installed as a LaunchAgent, but it is currently
  stopped.

  From /Users/gall/workspace/actions-runner, run these commands without sudo:

  cd /Users/gall/workspace/actions-runner

                                                # Check status
  ./svc.sh status

  # Start
                                                                                ./svc.sh start

                                                                         # Restart
  ./svc.sh stop
                                                                          ./svc.sh start

                                                                         If it isn’t installed as a service:

                                                    ./svc.sh install
  ./svc.sh start

  You can also run it interactively for troubleshooting:

  ./run.sh

  Interactive mode stops when that terminal closes. Service logs are under:

  ~/Library/Logs/actions.runner.galori-hub.hub-mbprm1-mbpro/

  Runner diagnostic logs are in:

  /Users/gall/workspace/actions-runner/_diag/
