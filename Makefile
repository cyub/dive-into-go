all:

serve:
	hugo serve

html:
	hugo

publish:
	ssh root@www.cyub.vip "cd /var/www/dive-into-go-v2; git pull"