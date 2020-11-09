import logging
import os

LOGGER_NAME = 'TermDebug'

def initLogging():
    logger = logging.getLogger(LOGGER_NAME)
    handler = logging.FileHandler('/tmp/termdebug.%s.log' % os.getenv('USER'), mode='w')
    formatter = logging.Formatter("%(asctime)s %(levelname)-8s %(name)s %(message)s")
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.setLevel(logging.DEBUG)

def getLogger():
    return logging.getLogger(LOGGER_NAME)

def log(msg):
    getLogger().debug(msg)


