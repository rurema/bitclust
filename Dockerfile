FROM ruby:3.3.3-bookworm
RUN apt-get update -y && apt-get install -y less
RUN useradd rurema --create-home --shell /bin/bash
USER rurema:rurema
ENV BUNDLE_AUTO_INSTALL true
WORKDIR /workspaces/bitclust
ENTRYPOINT ["bundle", "exec"]
CMD ["rake"]
