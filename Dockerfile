FROM registry-1.docker.io/library/golang:1.9-stretch

LABEL maintainer="Ugo Enyioha"

ARG VCS_REF
ARG BUILD_DATE

# Metadata
LABEL org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/uenyioha/croc-hunter" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.docker.dockerfile="/Dockerfile"

COPY . /go/src/github.com/lachie83/croc-hunter
COPY static/ static/

ENV GIT_SHA $VCS_REF
WORKDIR /go/src/github.com/lachie83/croc-hunter
RUN go install -v .

CMD ["croc-hunter"]

EXPOSE 8080
	
