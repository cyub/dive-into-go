all:

serve:
	hugo serve

html:
	hugo build

publish:
	ssh root@www.cyub.vip "cd /var/www/dive-into-go-v2; git pull"