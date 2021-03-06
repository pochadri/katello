#
# Copyright 2013 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

# a container represents a product or content view

class ContentSearch::ContainerSearch < ContentSearch::Search
  attr_accessor :rows, :name

  def container_hover_html(container, env)
    render_to_string :partial=>'content_search/container_hover',
      :locals=>{:container=>container, :env=>env}
  end

  def env_ids
    KTEnvironment.content_readable(current_organization).pluck(:id)
  end

end
